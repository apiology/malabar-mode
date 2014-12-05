;;; malabar-mode.el --- A better Java mode for Emacs

;; Copyright (c) Matthew O. Smith <matt@m0smith.com>
;;
;; Author: 
;;     Espen Wiborg <espenhw@grumblesmurf.org>
;;     Matthew Smith <matt@m0smith.com>
;; URL: http://www.github.com/m0smith/malabar-mode
;; Version: 1.6-M8
;; Package-Requires: ((fringe-helper "1.0.1"))
;; Keywords: java, maven, language, malabar

;;; License:

;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
;; 02110-1301 USA.
;;

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A Java Major Mode
;;

;;; Code:

(require 'groovy-mode)
(require 'semantic/db-javap)


;; 
;; init
;;

(setq ede-maven2-execute-mvn-to-get-classpath nil)

(semantic-mode 1)
(global-ede-mode 1)

;;
;; Groovy
;;


(defun malabar-run-groovy ()
  (interactive)
  (run-groovy (format "%s %s" (expand-file-name "~/.gvm/groovy/2.3.7/bin/groovysh")
		      " -Dhttp.proxyHost=proxy.ihc.com -Dhttp.proxyPort=8080 -Dgroovy.grape.report.downloads=true -Djava.net.useSystemProxies=true")))


(defun malabar-groovy-send-string (str)
  "Send a string to the inferior Groovy process."
  (interactive "r")

  (save-excursion
    (save-restriction
      (let ((proc (groovy-proc)))

      (with-current-buffer (process-buffer proc)
	(while (and
		(goto-char comint-last-input-end)
		(not (re-search-forward comint-prompt-regexp nil t))
		(accept-process-output proc)))
	(goto-char (process-mark proc))
	(insert-before-markers str)
	(move-marker comint-last-input-end (point))
	(comint-send-string proc str)
	(comint-send-string proc "\n")
	)
      )
    )))



(defun malabar-groovy-init-hook ()
  "Called when the inferior groovy is started"
  (interactive)
  (message "Starting malabar server")
  (malabar-groovy-send-string "def malabar = { classLoader = new groovy.lang.GroovyClassLoader();")
  (malabar-groovy-send-string "Map[] grapez = [[group: 'com.software-ninja' , module:'malabar', version:'2.0.4-SNAPSHOT']]")
  (malabar-groovy-send-string "groovy.grape.Grape.grab(classLoader: classLoader, grapez)")
  (malabar-groovy-send-string "classLoader.loadClass('com.software_ninja.malabar.MalabarStart').newInstance().startCL(classLoader); }; malabar();"))

(add-hook 'inferior-groovy-mode-hook 'malabar-groovy-init-hook)

(defun malabar-groovy-send-classpath  (pom &optional repo)
  "Add the classpath for POM to the runnning *groovy*."
  (interactive "fPOM File:")
  (mapcar (lambda (p) (malabar-groovy-send-string 
		       (format "this.getClass().classLoader.rootLoader.addURL(new File('%s').toURL())" (expand-file-name p)))) (malabar-project-classpath 
		     (malabar-project-info pom repo))))
  
;;;
;;; flycheck
;;;

(require 'flycheck)


(defadvice flycheck-start-command-checker (around flycheck-start-using-function act)
  "Put some nice docs here"
  (message "CHECKER: %s CALLBACK %s" checker callback)
  (let ((func (get checker 'flycheck-command-function)))
    (if func
	(apply func checker callback (flycheck-checker-substituted-arguments checker))
      ad-do-it)))


(defadvice flycheck-interrupt-command-checker (around flycheck-check-process-first-malabar act)
  (when process
      ad-do-it))

(defun malabar-flycheck-command ( checker callback source source-original)
  ""
  (let* ((pom (ede-find-project-root "pom.xml"))
	 (pom-path (format "%spom.xml" pom)))
    (message "command args:%s %s %s %s" (current-buffer) pom-path  source source-original)
    (let ((output (malabar-parse-script-raw pom-path source)))
      (message "parsed: %s" output)
      (flycheck-finish-checker-process checker 0 flycheck-temporaries output callback))))


(defun malabar-flycheck-error-new (checker error-info)
  ;;(message "error-info %s" error-info)
  (flycheck-error-new
   :buffer (current-buffer)
   :checker checker
   :filename (cdr (assq 'sourceLocator error-info))
   :line (cdr (assq     'line error-info))
   :column (cdr (assq   'startColumn error-info))
   :message (cdr (assq  'message error-info))
   :level 'error))

   

(defun malabar-flycheck-error-parser (output checker buffer)
  "Parse errors in result"
  (let ((rtnval (mapcar (lambda (e) (malabar-flycheck-error-new checker e)) (json-read-from-string output))))
    ;(flycheck-safe-delete-temporaries)
    rtnval))
	

(flycheck-define-checker jvm-mode-malabar
  ""
       :command ("echo" source source-original ) ;; use a real command
       :modes (java-mode groovy-mode)
       :error-parser malabar-flycheck-error-parser
)

(put 'jvm-mode-malabar 'flycheck-command-function 'malabar-flycheck-command)
(add-to-list 'flycheck-checkers 'jvm-mode-malabar)
(message "%s" (symbol-plist 'jvm-mode-malabar))

;;
;; EDE
;;

(defun malabar-maven2-load (dir &optional rootproj)
  "Return a Maven Project object if there is a match.
Return nil if there isn't one.
Argument DIR is the directory it is created for.
ROOTPROJ is nil, since there is only one project."
  (or (ede-files-find-existing dir ede-maven2-project-list)
      ;; Doesn't already exist, so lets make one.
       (let ((this
             (ede-maven2-project "Malabar Maven"
                                 :name "Malabar maven dir" ; TODO: make fancy name from dir here.
                                 :directory dir
                                 :file (expand-file-name "pom.xml" dir)
				 :current-target "package"
				 :classpath (mapcar 'identity (malabar-project-classpath (malabar-project-info (expand-file-name "pom.xml" dir))))
                                 )))
         (ede-add-project-to-global-list this)
         ;; TODO: the above seems to be done somewhere else, maybe ede-load-project-file
         ;; this seems to lead to multiple copies of project objects in ede-projects
	 ;; TODO: call rescan project to setup all data
	 (message "%s" this)
	 this)))


(ede-add-project-autoload
 (ede-project-autoload "malabar-maven2"
		       :name "MALABAR MAVEN2"
		       :file 'ede/maven2
		       :proj-file "pom.xml"
		       :proj-root 'ede-maven2-project-root
		       :load-type 'malabar-maven2-load
		       :class-sym 'ede-maven2-project
		       :new-p nil
		       :safe-p t
		       )
 'unique)

    
;;; Project

(require 'json)

(defvar url-http-end-of-headers)



(defun malabar-parse-script-raw (pom script &optional repo)
  "Parse the SCRIPT "
  (interactive "fPOM File:\nfJava File:")
  (let* ((repo (or repo (expand-file-name "~/.m2/repository")))
	 (url (format "http://localhost:4428/parse/?repo=%s&pom=%s&script=%s" repo (expand-file-name pom) (expand-file-name script))))
    (message "URL %s" url)
    (with-current-buffer (url-retrieve-synchronously url)
      (message "parse buffer %s" (current-buffer))
      (goto-char url-http-end-of-headers)
      (buffer-substring (point) (point-max)))))

(defun malabar-project-info (pom &optional repo)
  "Get the project info for a "
  (interactive "fPOM File:")
  (let* ((repo (or repo (expand-file-name "~/.m2/repository")))
	 (url (format "http://localhost:4428/pi/?repo=%s&pom=%s" repo (expand-file-name pom))))
    (with-current-buffer (url-retrieve-synchronously url)
      (goto-char url-http-end-of-headers)
      (json-read))))

(defun malabar-project-classpath (project-info)
  ""
  (interactive)
  (cdr (assq 'classpath (assq 'test project-info))))

;;(setq project-info (malabar-project-info "~/projects/malabar-mode-jar/pom.xml"))

