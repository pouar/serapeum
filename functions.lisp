(in-package :serapeum)
(in-readtable :fare-quasiquote)

(export '(flip nth-arg
          distinct
          throttle #+ () debounce
          juxt
          dynamic-closure))

(defun eqs (x)
  "A predicate for equality (under EQ) with X."
  (lambda (y) (eq x y)))

(define-compiler-macro eqs (x)
  (once-only (x)
    `(lambda (y) (eq ,x y))))

(defun eqls (x)
  "A predicate for equality (under EQL) with X."
  (lambda (y) (eql x y)))

(define-compiler-macro eqls (x)
  (once-only (x)
    `(lambda (y) (eql ,x y))))

(defun equals (x)
  "A predicate for equality (under EQUAL) with X."
  (lambda (y)
    (equal y x)))

(define-compiler-macro equals (x)
  (once-only (x)
    `(lambda (y) (equal ,x y))))

;;; It would of course be possible to define `flip' to be variadic,
;;; but the binary case can be handled more efficiently, and I have
;;; not seen any other uses for it.

(defun flip (f)
  "Flip around the arguments of a binary function.

That is, given a binary function, return another, equivalent function
that takes its two arguments in the opposite order.

From Haskell."
  (let ((f (ensure-function f)))
    (lambda (x y)
      (funcall f y x))))

(define-compiler-macro flip (fn)
  (rebinding-functions (fn)
    `(lambda (x y)
       (funcall ,fn y x))))

(defun nth-arg (n)
  "Return a function that returns only its NTH argument, ignoring all others.

If you've ever caught yourself trying to do something like

    (mapcar #'second xs ys)

then `nth-arg` is what you need.

If `hash-table-keys` were not already defined by Alexandria, you could
define it thus:

    (defun hash-table-keys (table)
      (maphash-return (nth-arg 0) table))"
  (lambda (&rest args)
    (declare (dynamic-extent args))
    (nth n args)))

(define-compiler-macro nth-arg (n)
  (let ((leading (loop repeat n collect (gensym))))
    (with-gensyms (arg rest)
      `(lambda (,@leading ,arg &rest ,rest)
         (declare (ignore ,@leading ,rest))
         ,arg))))

(defun distinct (&key (key #'identity)
                      (test 'equal))
  "Return a function that echoes only values it has not seen before.

    (defalias test (distinct))
    (test 'foo) => foo, t
    (test 'foo) => nil, nil

The second value is T when the value is distinct.

TEST must be a valid test for a hash table.

This has many uses, for example:

    (count-if (distinct) seq)
    ≡ (length (remove-duplicates seq))"
  (check-type test ok-hash-table-test)
  (let ((dict (make-hash-table :test test))
        (key (ensure-function key)))
    (lambda (arg)
      (if (nth-value 1 (gethash arg dict))
          (values nil nil)
          (values (setf (gethash arg dict)
                        (funcall key arg))
                  t)))))

(defun throttle (fn wait &key synchronized)
  "Wrap FN so it can be called no more than every WAIT seconds.
If FN was called less than WAIT seconds ago, return the values from the
last call. Otherwise, call FN normally and update the cached values.

WAIT, of course, may be a fractional number of seconds.

The throttled function is not thread-safe by default; use SYNCHRONIZED
to get a version with a lock."
  (let* ((fn (ensure-function fn))
         (thunk
           (let ((last 0)
                 (cache '(nil)))
             (lambda (&rest args)
               (when (<= (- wait (- (get-universal-time) last)) 0)
                 (setf last (get-universal-time)
                       cache (multiple-value-list (apply fn args))))
               (values-list cache)))))
    (if (not synchronized)
        thunk
        (let ((lock (bt:make-lock)))
          (lambda (&rest args)
            (bt:with-lock-held (lock)
              (apply thunk args)))))))

(defun once (fn)
  "Return a function that runs FN only once, caching the results
forever."
  (let ((cache '(nil))
        (first-run t))
    (lambda (&rest args)
      (if (not first-run)
          (values-list cache)
          (setf first-run nil
                cache (multiple-value-list (apply fn args)))))))

(defun juxt (&rest fns)
  "Clojure's `juxt'.

Return a function of one argument, which, in turn, returns a list
where each element is the result of applying one of FNS to the
argument.

It’s actually quite simple, but easier to demonstrate than to explain.
The classic example is to use `juxt` to implement `partition`:

    (defalias partition* (juxt #'filter #'remove-if))
    (partition* #'evenp '(1 2 3 4 5 6 7 8 9 10))
    => '((2 4 6 8 10) (1 3 5 7 9))

The general idea is that `juxt` takes things apart."
  (lambda (&rest args)
    (declare (dynamic-extent args))
    (loop for fn in fns
          collect (apply fn args))))

(define-compiler-macro juxt (&rest fns)
  (let ((gs (loop for nil in fns collect (gensym "FN"))))
    (with-gensyms (args)
      `(let ,(loop for g in gs
                   for fn in fns
                   collect `(,g (ensure-function ,fn)))
         (lambda (&rest ,args)
           (declare (dynamic-extent ,args))
           (list ,@(loop for g in gs collect `(apply ,g ,args))))))))

(assert (equal (funcall (juxt #'remove-if-not #'remove-if)
                        #'evenp
                        '(1 2 4 3 5 6))
               '((2 4 6) (1 3 5))))

(assert (equal (funcall (juxt #'+ #'max #'min) 2 3 5 1 6 4)
               '(21 6 1)))

(defun key-test (key test)
  "Return a function of two arguments which uses KEY to extract the
part of the arguments to compare, and compares them using TEST.

If MEMO is non-nil, memoize KEY function."
  (ensuring-functions (key test)
    (lambda (x y)
      (funcall test (funcall key x) (funcall key y)))))

(define-compiler-macro key-test (key test)
  (rebinding-functions (key test)
    `(lambda (x y)
       (funcall ,test
                (funcall ,key x)
                (funcall ,key y)))))

(defun dynamic-closure (symbols fn)
  "Create a dynamic closure.

Some ancient Lisps had closures without lexical binding. Instead, you
could \"close over\" pieces of the current dynamic environment. When
the resulting closure was called, the symbols closed over would be
bound to their values at the time the closure was created. These
bindings would persist through subsequent invocations and could be
mutated. The result was something between a closure and a
continuation.

This particular piece of Lisp history is worth reviving, I think, if
only for use with threads. For example, to start a thread and
propagate the current value of `*standard-output*':

     (bt:make-thread (dynamic-closure '(*standard-output*) (lambda ...)))
     = (let ((temp *standard-output*))
         (bt:make-thread
          (lambda ...
            (let ((*standard-output* temp))
              ...))))"
  (let ((fn (ensure-function fn))
        (values (mapcar #'symbol-value symbols)))
    (lambda (&rest args)
      (declare (dynamic-extent args))
      (progv symbols values
        (multiple-value-prog1
            (apply fn args)
          (map-into values #'symbol-value symbols))))))

(define-compiler-macro dynamic-closure (&whole decline
                                               symbols fn)
  (match symbols
    (`(quote ,symbols)
      (let ((temps (make-gensym-list (length symbols))))
        (rebinding-functions (fn)
          `(let ,(mapcar #'list temps symbols)
             (lambda (&rest args)
               (declare (dynamic-extent args))
               (let ,(mapcar #'list symbols temps)
                 (multiple-value-prog1
                     (apply ,fn args)
                   (setf ,@(mappend #'list temps symbols)))))))))
    (otherwise decline)))

(let ((fn (lambda ()
           (write-string "Hello")
           (get-output-stream-string *standard-output*))))
  (assert (equal "Hello"
                 (funcall (let ((*standard-output* (make-string-output-stream)))
                            (dynamic-closure '(*standard-output*) fn)))))
  (assert (equal "Hello"
                 (funcall (let ((*standard-output* (make-string-output-stream))
                                (symbols '(*standard-output*)))
                            (dynamic-closure symbols fn))))))
