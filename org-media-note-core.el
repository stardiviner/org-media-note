;;; org-media-note-core.el --- Core for org-mode-note -*- lexical-binding: t; -*-


;;; Commentary:
;;; Code:
;;;; Requirements
(require 'mpv)
(require 'org)

(declare-function org-timer-secs-to-hms "org-timer")
(declare-function org-timer-hms-to-secs "org-timer")
(declare-function org-attach-dir "org-attach")

;;;; Customization

(defgroup org-media-note nil
  "Taking video and audio notes with Org-mode."
  :group 'org
  :prefix "org-media-note-")

(defcustom org-media-note-screenshot-save-method 'directory
  "The way images should be stored.
1. directory: save to `org-media-note-screenshot-image-dir'
2. attach: save to corresponding org-attach-dir."
  :type '(choice
          (const :tag "Directory" directory)
          (const :tag "Attachment" attach)))

(defcustom org-media-note-screenshot-link-type-when-save-in-attach-dir 'file
  "Use file link or attachment link when `org-media-note-screenshot-save-method' is attach?
file link is more general while attachment link is more concise."
  :type '(choice
          (const :tag "file:" file)
          (const :tag "attachment:" attach)))

(defcustom org-media-note-screenshot-image-dir org-directory
  "Default dir to save screenshots when `org-media-note-screenshot-save-method' is set to directory."
  :type 'string)

(defcustom org-media-note-save-screenshot-p nil
  "Whether to auto save screenshot when insert media link."
  :type 'boolean)

(defcustom org-media-note-screenshot-with-sub t
  "When saving screenshots, whether to save subtitles."
  :type 'boolean)

(defcustom org-media-note-use-refcite-first nil
  "When non-nil, use refcite instead of file path when taking notes if possible."
  :type 'boolean)

(defcustom org-media-note-display-inline-images t
  "When non-nil, display inline images in org buffer after insert screenshot."
  :type 'boolean)

(defcustom org-media-note-pause-after-insert-link nil
  "When non-nil, pause the media after inserting timestamp link."
  :type 'boolean
  )

(defcustom org-media-note-timestamp-link-format "%timestamp"
  "Timestamp Link text.  Allows the following substitutions:
%filename :: name of the media file
%timestamp :: current media timestamp (hms)
%duration :: length of the media file (hms)
%file-path :: path of the media file"
  :type 'string)

(defcustom org-media-note-ab-loop-link-format "%ab-loop-a-%ab-loop-b"
  "AB-loop Link text.  Allows the following substitutions:
%filename :: name of the media file
%ab-loop-a :: timestamp of point a of ab loop (hms)
%ab-loop-b :: timestamp of point b of ab loop (hms)
%duration :: length of the media file (hms)
%file-path :: path of the media file"
  :type 'string)

(defcustom org-media-note-cursor-start-position 'after
  "After inserting a link, should the cursor move to the point
before the link, or the point after?"
  :type 'symbol
  :options '(before after))

(defcustom org-media-note-link-prefix ""
  "Whether to prefix the link text with any text that is
not part of the link.  Most common use is to insert a space
that is not part of the link if the user sets
`org-media-note-cursor-start-position' to 'before, they likely
want a space that is not part of the link itself."
  :type 'string)

;;;; Variables

(defconst org-media-note--video-types '("avi" "rmvb" "ogg" "ogv" "mp4" "mkv" "mov" "webm" "flv" "ts" "mpg"))
(defconst org-media-note--audio-types '("flac" "mp3" "wav"))
(defconst org-media-note--timestamp-pattern "\\([0-9]+:[0-9]+:[0-9]+\\)[ \t]?")

;;;; Commands
;;;;; Utils

(defun org-media-note--seconds-to-hms (secs)
  "Convert secs (float or int) to hms (string)"
  (org-timer-secs-to-hms (round secs)))

(defun org-media-note--millisecs-to-hms (millisecs)
  (org-media-note--seconds-to-hms (/ (string-to-number millisecs)
                                     1000)))

(defun org-media-note--get-duration-hms ()
  "Get the current media duration in format h:mm:ss"
  (org-media-note--seconds-to-hms (mpv-get-duration)))

(defun org-media-note--get-current-hms ()
  "Get current media timestamp in format h:mm:ss"
  (org-media-note--seconds-to-hms (mpv-get-playback-position)))

(defun org-media-note--current-org-ref-key ()
  (org-entry-get (point) "Custom_ID"))

(defun org-media-note--current-media-type ()
  "Get current playing media type."
  (let* ((file-path (mpv-get-property "path")))
    (if (org-media-note--online-video-p file-path)
        "video" ;; TODO online audio?
      (org-media-note--file-media-type file-path))))

(defun org-media-note--file-media-type (file-path)
  "Get file media type."
  (let* ((file-ext (if file-path
                       (file-name-extension file-path))))
    (org-media-note--get-media-type file-ext)))

(defun org-media-note--get-media-type (file-ext)
  (cond
   ((member file-ext org-media-note--video-types) "video")
   ((member file-ext org-media-note--audio-types) "audio")
   (t nil)))

(defun org-media-note-ref-cite-p ()
  "Whether to use refcite link instead of file path."
  (and (org-media-note--current-org-ref-key)
       org-media-note-use-refcite-first))

(defun org-media-note--online-video-p (path)
  (string-match "^http" path))

;;;;; Add note
;;;;;; media note item

(defun org-media-note-insert-link ()
  "Insert current mpv timestamp link into Org-mode note."
  (interactive)
  (let ((point (point)))
    (insert org-media-note-link-prefix
            (format "%s "
                    (org-media-note--link)))
    (when (eq org-media-note-cursor-start-position 'before)
      (goto-char point))
    (when org-media-note-pause-after-insert-link
      (mpv-pause))))

(defun org-media-note--link ()
  "Return media link."
  (let* ((file-path (mpv-get-property "path"))
         (link-type (if (org-media-note-ref-cite-p)
                        (concat (org-media-note--current-media-type)
                                "cite")
                      (org-media-note--current-media-type)))
         (filename (mpv-get-property "media-title"))
         (duration (org-media-note--get-duration-hms))
         (timestamp (org-media-note--get-current-hms)))
    (if (org-media-note--ab-loop-p)
        ;; ab-loop link
        (let ((time-a (org-media-note--seconds-to-hms (mpv-get-property "ab-loop-a")))
              (time-b (org-media-note--seconds-to-hms (mpv-get-property "ab-loop-b"))))
          (format "[[%s:%s#%s-%s][%s]]"
                  link-type
                  (org-media-note--link-base-file file-path)
                  time-a
                  time-b
                  (org-media-note--link-formatter org-media-note-ab-loop-link-format
                                                  `(("filename" . ,filename)
                                                    ("duration" . ,duration)
                                                    ("ab-loop-a" . ,time-a)
                                                    ("ab-loop-b" . ,time-b)
                                                    ("file-path" . ,file-path)))))
      ;; timestamp link
      (format "[[%s:%s#%s][%s]]"
              link-type
              (org-media-note--link-base-file file-path)
              timestamp
              (org-media-note--link-formatter org-media-note-timestamp-link-format
                                              `(("filename" . ,filename)
                                                ("duration" . ,duration)
                                                ("timestamp" . ,timestamp)
                                                ("file-path" . ,file-path)))))))

(defun org-media-note--ab-loop-p ()
  "Whether in ab-loop?"
  (let ((time-a (mpv-get-property "ab-loop-a"))
        (time-b (mpv-get-property "ab-loop-b"))
        (pos (mpv-get-playback-position)))
    (and (numberp time-a)
         (numberp time-b)
         (<= time-a pos)
         (<= pos time-b))))

(defun org-media-note--link-base-file (file-path)
  (if (org-media-note-ref-cite-p)
      (org-media-note--current-org-ref-key)
    (if (org-media-note--online-video-p file-path)
        file-path
      (org-media-note--format-file-path file-path))))

(defun org-media-note--link-formatter (string map)
  "MAP is an alist in the form of '((PLACEHOLDER . REPLACEMENT))
STRING is the original string.  Each placeholder can be a string,
symbol, or number. REPLACEMENT can be a string, a number, symbol,
or function. Replace all occurrences of %placeholder with replacement
and return a new string.

For example:
(let ((input-string  \"Words,  %test1%test2 more words %test1.\")
      (map '((test1 . \"asdf\")
             (test2 . \"zxcv\"))))
  (org-media-note--link-formatter input-string map))

Returns:
\"Words,  asdfzxcv more words asdf.\""
  (cl-loop for (holder . replacement) in map
	   when replacement
	   do (setq string
		    (replace-regexp-in-string
		     (concat "%"
			     (pcase holder
			       ((pred symbolp) (symbol-name holder))
			       ((pred stringp) holder)
			       ((pred numberp) (number-to-string holder))
			       ((pred functionp) (funcall replacement))))
		     (pcase replacement
		       ((pred symbolp) (symbol-name holder))
		       ((pred stringp) replacement)
		       ((pred numberp) (number-to-string replacement))
		       ((pred functionp) (funcall replacement))
		       (_ ""))
		     string))
	   finally return string))

(defun org-insert-item--media-note-item (orig-fn &rest args)
  "When item begins with media link, insert playback position."
  (interactive "P")
  (let ((itemp (org-in-item-p))
        (pos (point)))
    ;; If cursor isn't is a list or if list is invisible, return nil.
    (unless (or (not itemp)
                (save-excursion
                  (goto-char itemp)
                  (org-invisible-p)))
      (if (save-excursion
            (goto-char itemp)
            (org-media-note--at-media-item-p))
          (progn
            (org-media-note-item)
            t)))))

(defun org-media-note--at-media-item-p ()
  "Is point at a line starting a plain list item with a media-note link?"
  (or (org-list-at-regexp-after-bullet-p "\\(\\[\\[video.+\\)")
      (org-list-at-regexp-after-bullet-p "\\(\\[\\[audio.+\\)")))

(defun org-media-note-item (&optional arg)
  "Insert a item with the link to media file."
  (interactive "P")
  (let ((itemp (org-in-item-p))
        (pos (point)))
    (cond
     ;; In a media note list and media file is open: insert with `org-list-insert-item',
     ((and itemp
           (goto-char itemp)
           (org-media-note--at-media-item-p)
           (mpv-get-property "path"))
      (let* ((struct (org-list-struct))
             (prevs (org-list-prevs-alist struct))
             (s (concat (org-media-note--link)
                        " ")))
        (setq struct (org-list-insert-item pos struct prevs nil
                                           s))
        (org-list-write-struct struct
                               (org-list-parents-alist struct))
        (looking-at org-list-full-item-re)
        (move-end-of-line 1)
        (when org-media-note-pause-after-insert-link
          (mpv-pause))
        (when org-media-note-save-screenshot-p
          (org-media-note-insert-screenshot))))
     ;; In a list of another type, don't break anything: throw an error.
     (t (error (concat "No playing media file now. Please open the media file"
                       "first if you want to insert media note,"
                       "\nor turn off "))))))

;;;;;; screenshot
(defun org-media-note-insert-screenshot ()
  "Insert current mpv screenshot into Org-mode note."
  (interactive)
  (let* ((image-file-name (org-media-note--format-picture-file-name (concat (file-name-base (mpv-get-property "path"))
                                                                    "-"
                                                                    (org-media-note--get-current-hms)
                                                                    ".jpg"))) ;; TODO let user customize this
         (image-target-path (cond
                             ((eq org-media-note-screenshot-save-method
                                  'attach)
                              (expand-file-name image-file-name
                                                (org-attach-dir t)))
                             ((eq org-media-note-screenshot-save-method
                                  'directory)
                              (expand-file-name image-file-name org-media-note-screenshot-image-dir)))))
    (if org-media-note-screenshot-with-sub
        (mpv-run-command "screenshot-to-file" image-target-path)
      (mpv-run-command "screenshot-to-file" image-target-path "video"))
    (if (and (eq org-media-note-screenshot-save-method
                 'attach)
             (eq org-media-note-screenshot-link-type-when-save-in-attach-dir
                 'attach))
        (insert (format "[[attachment:%s]] "
                        (file-relative-name image-target-path
                                            (org-attach-dir))))
      (insert (format "[[file:%s]] "
                      (org-media-note--format-file-path image-target-path))))
    (org-media-note--display-inline-images)))

(defun org-media-note--format-picture-file-name (name)
  (let (new-name)
    (setq new-name (replace-regexp-in-string " - " "-" name))
    (setq new-name (replace-regexp-in-string ":" "_" name))
    (replace-regexp-in-string " " "_" new-name)))

(defun org-media-note--format-file-path (path)
  "Convert PATH into the format defined by `org-link-file-path-type'"
  (cond
   ((eq org-link-file-path-type 'absolute)
    (abbreviate-file-name (expand-file-name path)))
   ((eq org-link-file-path-type 'noabbrev)
    (expand-file-name path))
   ((eq org-link-file-path-type 'relative)
    (file-relative-name path))
   ((eq org-link-file-path-type 'adaptive)
    (save-match-data (if (string-match (concat "^"
                                               (regexp-quote (expand-file-name (file-name-as-directory default-directory))))
                                       (expand-file-name path))
                         ;; We are linking a file with relative path name.
                         (substring (expand-file-name path)
                                    (match-end 0))
                       (abbreviate-file-name (expand-file-name path)))))
   ((functionp org-link-file-path-type)
    (funcall org-link-file-path-type
             (expand-file-name path)))))

(defun org-media-note--display-inline-images ()
  (when org-media-note-display-inline-images
    ;; TODO beteer way?
    (sleep-for 0.1)
    (org-display-inline-images)))

;;;;;; sub-text
(defun org-media-note-insert-sub-text ()
  (interactive)
  (let ((sub-text (condition-case nil
                      (mpv-get-property "sub-text")
                    (error nil))))
    (if sub-text
        (insert sub-text)
      (message "No subtitles found in current file."))))
;;;;; Adjust timestamp

(defun org-media-note-adjust-timestamp-offset ()
  (interactive)
  (let* ((current-playing-position (mpv-get-playback-position)) link
         current-link-position
         offset)
    (cl-multiple-value-bind (_ _ link _)
        (org-link-edit--link-data)
      (let* ((splitted (split-string link "#"))
             (timestamps (split-string (nth 1 splitted))))
        (setq current-link-position (org-timer-hms-to-secs (nth 0 timestamps)))
        (setq offset (- current-playing-position current-link-position))))
    (save-excursion
      (org-narrow-to-subtree)
      (goto-char (point-min))
      (while (re-search-forward org-media-note--timestamp-pattern
                                nil t)
        (let* ((beg (match-beginning 1))
               (end (match-end 1))
               (hms (buffer-substring beg end))
               (adjusted-hms (org-media-note--seconds-to-hms (+ (org-timer-hms-to-secs hms)
                                                                offset))))
          (goto-char beg)
          (delete-region beg end)
          (insert adjusted-hms)))
      (widen))))

;;;;; Link Follow
(defun org-media-note-media-link-follow (link)
  "Open video and audio links, supported formats:
1. video:example.mkv#0:02:13: jump to 0:02:13
2. video:example.mkv#0:02:13-0:02:20: jump to 0:02:13 and loop between 0:02:13 and 0:02:20
"
  (let* ((splitted (split-string link "#"))
         (file-path-or-url (nth 0 splitted))
         (timestamps (split-string (nth 1 splitted)
                                   "-"))
         (time-a (int-to-string (org-timer-hms-to-secs (nth 0 timestamps))))
         (time-b (if (= (length timestamps) 2)
                     (int-to-string (org-timer-hms-to-secs (nth 1 timestamps))))))
    (org-media-note--follow-link file-path-or-url time-a time-b)))

(defun org-media-note--follow-link (file-path-or-url time-a time-b)
  (let ((path (if (org-media-note--online-video-p file-path-or-url)
                       file-path-or-url
                     (expand-file-name file-path-or-url))))
    (if (not (string= path
                      (mpv-get-property "path")))
        ;; file-path is not playing
        (if time-b
            (mpv-start path
                       (concat "--start=+" time-a)
                       (concat "--ab-loop-a=" time-a)
                       (concat "--ab-loop-b=" time-b))
          (mpv-start path
                     (concat "--start=+" time-a)))
      ;; file-path is playing
      ;; TODO clear a-b loop when only one timestamp?
      (progn
        (when time-b
          (mpv-set-property "ab-loop-a" time-a)
          (mpv-set-property "ab-loop-b" time-b))
        (mpv-seek time-a)))))

;;;; Footer
(provide 'org-media-note-core)
;;; org-media-note-core.el ends here
