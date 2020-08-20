(in-package :serapeum)

(uiop:define-package :serapeum.exporting
  (:use)
  (:export :defclass :define-values))

(defmacro serapeum.exporting:defclass (name supers &body (slots . options))
  "Like `defclass', but implicitly export the name of the class and
the names of all accessors (including readers and writers)."
  (let (accessors)
    (dolist (slot slots)
      (destructuring-bind (&key accessor reader writer &allow-other-keys)
          (rest (ensure-list slot))
        (when accessor (push accessor accessors))
        (when reader (push reader accessors))
        (when writer (push writer accessors))))
    (setf accessors (remove-duplicates accessors))
    `(progn
       (export-always ',(cons name accessors))
       (defclass ,name ,supers
         ,slots
         ,@options))))

(defmacro serapeum.exporting:define-values (values &body (expr))
  `(progn
     (export-always ',values)
     (define-values ,values ,expr)))

(defmacro define-simple-exporter (macro-name lambda-list)
  (with-unique-names (whole)
    (let ((name-sym (first lambda-list))
          (exporter-name (intern (string macro-name)
                                 (find-package :serapeum.exporting))))
      `(progn
         (export-always '(,exporter-name)
             (find-package :serapeum.exporting))
         (defmacro ,exporter-name (&whole ,whole ,@lambda-list)
           (declare (ignore ,@(set-difference (flatten (rest lambda-list))
                                              lambda-list-keywords)))
           (list 'progn
                 (list 'export-always (list 'quote ,name-sym))
                 (cons ',macro-name (rest ,whole))))))))

(define-simple-exporter def (var &body (&optional val docs)))

(define-simple-exporter define-symbol-macro (symbol expansion))

(define-simple-exporter deftype (name lamda-list &body body))

(define-simple-exporter defconst (symbol init &optional docstring))

(define-simple-exporter defconstant (name value &optional doc))

(define-simple-exporter defvar (var &optional val doc))

(define-simple-exporter defparameter (var val &optional doc))

(define-simple-exporter defun (name lambda-list &body body))

(define-simple-exporter defalias (name &body body))

(define-simple-exporter defmacro (name &body body))

(define-simple-exporter defgeneric (name lambda-list &body options))

(define-simple-exporter defmethod (name &body args))
