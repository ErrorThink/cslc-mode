;;; cslc-mode.el --- Minor mode for recording live code sessions with Csound. -*- lexical-binding: t; -*-

;; Copyright (C) 2024, Thorin Kerr

;; Author: Thorin Kerr <thorin.kerr@gmail.com>
;; Keywords: livecoding live-coding csound
;; Compatibility: GNU Emacs 25.2.2
;; Version: 0.2
 
;; This file is NOT part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;; Package-Requires: ((heap "0.5"))

;;; Commentary:
;; This package provides functions which send code
;; to an instance of Csound running in an external terminal.
;; Additional features Record and play back the 'typed' live code sessions 
;; from multiple buffers.

;; FEATURES
;; --------------
;; - Launch a terminal running Csound (default ANSI-TERM)
;; - Set a default CSD to run with csound
;; - Record/playback and re-record multiple live code sessions in multiple buffers.
;; - Edit code within the same buffer as playback (experimental).

;; Getting Started
;; 1. Launch Csound (M-x cslc-start-process).
;; 2. In an empty buffer start recording (M-x cslc-start-recording)
;; 3. Live code your csound session.
;; 4. When you've finished your session, stop recording (M-x cslc-stop-recording).
;; You may want to stop csound too (M-x cslc-stopcsound).
;; 4(a). Not happy with your performance?
;; Remove this session from the recording (M-x cslc-remove-recorded-session <RET>).
;; 5. In an new empty buffer start recording (M-x cslc-start-recording).
;; Playback of the previous session(s) will begin automatically while you record.
;; 6. Repeats steps 4 and 5 to record as many sessions as you need.
;; 6(a) Recording a new session in a previously recorded buffer
;; will increment a numbered suffix in the buffer name with '-Take[n]'.
;; When finishing a new 'Take' you may then want to delete the previous Take from *TIMEQUEUE*
;; (M-x cslc-remove-recorded-session <buffer-to-remove>)
;;
;; Performance Recordings are stored in the file ~/*TIMEQUEUE*.
;; Rename and save this file for posterity. 
;;
;; Default keybindings (Re-bind these to something more convenient)
;; C-c & `cslc-start-process' launches a process and a terminal running csound. 
;; C-c C-SPC `cslc-eval-instrument' - Send the instrument or UDO definition to Csound 
;; C-c , `cslc-eval-region' - Send the selected (active) region to Csound
;; C-c . `cslc-eval-line' - Send the line to Csound 
;; C-c $ `cslc-start-recording' - Record a performance in the buffer.
;; C-c % `cslc-stop-recording' - Stop recording the performance (all buffers)
;; C-c ^ `cslc-play-recording' - Play a recorded performance.
;; C-c <down> `cslc-next-instrument' - Move the cursor to the next instrument in the buffer
;; C-c <up> `cslc-previous-instrument' - Move the cursor to the previous instrument in the buffer
;;
;; Other functions
;; A number of other convenience functions are also provided, all with the prefix
;; `cslc-'. 
;; Functions with prefix `cslc--' (double hyphen) are for internal use only, and
;; should not be used outside this package.
;;
;; `cslc-settings' - Prompt to save default settings when Csound launches.
;; `cslc-create-performance-buffers' - Creates the buffers recorded in *TIMEQUEUE* without beginning the performance.
;; `cslc-pause-playback' - Pause the playback of a recording.
;; `cslc-resume-playback' - Resume the playback of a paused recording.
;; `cslc-toggle-pause-recording' - Pause / Resume playback of a recording.
;; `cslc-remove-recorded-session' - Prompt to remove a recorded session of a buffer from *TIMEQUEUE*.     
;; `cslc-timeshift-recorded-session' - Shift timestamps of a recorded buffer session by n seconds.
;; `cslc-set-buffer-playback-speed' - Sets the playback speed of a recorded performance.
;; `cslc-increment-buffer-playback-speed' - increase the playback speed.
;; `cslc-increment-buffer-playback-speed' - decrease the playback speed.
;; `cslc-original-buffer-playback-speed' - return to normal playback speed
;;  ---- For use with cslc-lib.csd as a default csd (optional):
;; `cslc-new-scheduler' - insert a template for a tempo recursion instrument
;; `cslc-new-instr' - insert a template for a a source instrument
;; `cslc-new-effect' - insert a template for an effect instrument
;; `cslc-monophonic-insert' - code snippet to force monophony in an instrument
;; `cslc-stopcsound' - Stop Csound.

;; Custom group variables
;; Set these via the minibuffer with the command `customize-group' <RET> `cslc'
;; Or with prompts from the command `cslc-settings'
;; `cslc-host' - network address of the csound process
;; `cslc-port' - port to use to send csound messages
;; `cslc-term' - command to run the external terminal
;; `cslc-csound-command' - command to launch csound with in the external terminal. 
;; `cslc-init-csd' - Path to default csd to run when launching csound. 
;;
;; Dependencies
;; Requires heap.el data structure library by Tony Cubitt
;;   Available from MELPA or https://www.dr-qubit.org/emacs_data-structures.html
;; Csound should be installed (or somewhere accessible on a network).
;; (See https://csound.com/download.html)
;; cslc-mode autoloads when csound-mode major mode is activated.
;  (See MELPA or https://github.com/hlolli/csound-mode)
;;
;; Installation
;; Put cslc-mode.el in your load-path.
;; Add the following to your ~/.emacs startup file.
;; (require 'cslc-mode)
;;
;;
;; To DO
;; CSD output of a performance
;; Advice online suggests find-file-noselect is problematic. Replace this.
;;; Code:

;;Public Interface Functions ;;;;;;;;;;;;;;;;;;;;;;;

(message "RUNNING CSLC")

(require 'generator)
(require 'cl-lib)
(require 'heap)

(defgroup cslc-mode nil
  "Paths to cslc-mode settings"
  :group 'cslc
  :prefix "cslc-")

(defcustom cslc-init-csd ""
  "Path to a csd with which to Start Csound. 
Expects a string path. 
Useful for loading instruments and opcode libraries at startup."
  :group 'cslc
  :type 'string)

(defcustom cslc-port "8099"
  "Port to use to send to Csound." 
  :group 'cslc
  :type 'string)

(defcustom cslc-csound-command (concat (if (executable-find "csound.exe") "csound.exe " "csound ") "-odac --port=8099 --sample-rate=48000 --ksmps=64 --nchnls=2 --0dbfs=1 --nodisplays --messagelevel=1120")
  "Command to launch Csound.
Note that these over-ride csd flags"
  :group 'cslc
  :type 'string)


(defcustom cslc-host "127.0.0.1"
  "Port to use to send to Csound." 
  :group 'cslc
  :type 'string)

(defcustom cslc-term '(ansi-term "/bin/bash" "cslc-term")
  "external terminal to launch" 
  :group 'cslc
  :type 'list)

(defun cslc-next-instrument ()
  "Move cursor to the next instrument after the current point in the buffer"
  (interactive)
  (let ((result (re-search-forward "\\(^instr \\|^opcode\s\\|^loopcode\\|^loopevent\\|^EffectConstruct\\)" nil t nil)))
    (if (not result)
	(progn
	  (goto-char (point-min))
	  (re-search-forward "\\(^instr \\|^opcode\s\\|^loopcode\\|^loopevent\\|^EffectConstruct\\)" nil t nil)))
    (end-of-line)))

(defun cslc-previous-instrument ()
  "Move cursor to the previous instrument in the buffer"
  (interactive)
  (beginning-of-line)
  (let ((result (re-search-backward "\\(^instr \\|^opcode\s\\|^loopcode\\|^loopevent\\|^EffectConstruct\\)" nil t nil)))
    (if (not result)
	(progn
	  (goto-char (point-max))
	  (re-search-backward "\\(^instr \\|^opcode\s\\|^loopcode\\|^loopevent\\|^EffectConstruct\\)" nil t nil)))
    (end-of-line)))

;;;Private Variables

(defvar cslc--csd-clock (current-time))
;; More relevant when CSD-output is implemented

(defvar cslc--icount nil)
(setq cslc--icount 100)

(defvar cslc--scount nil)
(setq cslc--scount 10)

(defvar cslc--fxcount nil)
(setq cslc--fxcount 200)

(defun cslc--get-inumber ()
  (setq cslc--icount (1+ cslc--icount))
  (number-to-string cslc--icount))

(defun cslc--get-snumber ()
  (setq cslc--scount (1+ cslc--scount))
  (number-to-string cslc--scount))

(defun cslc--get-fxnumber ()
  (setq cslc--fxcount (1+ cslc--fxcount))
  (number-to-string cslc--fxcount))

;;;; Public Code Templates
;;;; Designed for use with the csound file CSLCSetupLib.csd. Ignore if you're live coding your own way.
(defun cslc-new-scheduler ()
  "Template for a tempo recursion instrument"
  (interactive)
  (save-excursion (insert "instr Sched" (cslc--get-snumber) "

schedule p1, nextbeat(1), 1

turnoff
endin

schedule \"Sched" (number-to-string cslc--scount) "\", array(1,1)
"))
  (next-line))


(defun cslc-new-instr ()
  "Template for a sound source instrument"
  (interactive)
  (save-excursion
    (insert "instr Sound" (cslc--get-inumber) "

send ares
endin

patchsig \"Sound" (number-to-string cslc--icount) "\", \"outs\"
schedule \"Sound" (number-to-string cslc--icount) "\", nextbeat(1), tempodur(1),0.5,cpstuni(0,gi_CurrentScale)
"))
  (next-line))

(defun cslc-new-effect ()
  "Template for an effect instrument"  
  (interactive)
  (save-excursion
    (insert "EffectConstruct \"Effect" (cslc--get-fxnumber) "\", {{
ain = ains[0]

aouts[] fillarray aout1;, aout2
}},1,1

patchsig \"Effect"(number-to-string cslc--fxcount) "\", \"outs\"
")))

(defun cslc-monophonic-insert ()
  "code snippet to force monophony in an instrument"  
  (interactive)
  (save-excursion (insert "if mono()==1 then
    turnoff
endif"))
  (next-line))

(defun cslc-insert-livecsd-tags ()
  "Insert csd tags in the buffer for live performance"
  (interactive)
  (goto-char (point-min))
  (insert "<CsoundSynthesizer>
<CsOptions>
--port=8099 -odac --nchnls=2 --0dbfs=1 --nodisplays --sample-rate=48000 --ksmps=120 --realtime --sample-accurate -B960 -b240 --messagelevel=70
</CsOptions>
<CsInstruments>")
  (goto-char (point-max))
  (insert "
</CsInstruments>
</CsoundSynthesizer>"))

(defun cslc-insert-fileout-csd-tags ()
  "Insert csd tags in the buffer for audio file output"
  (interactive)
  (let ((end-time (number-to-string (float-time (time-since cslc--csd-clock)))))
    (goto-char (point-min))
    (insert "<CsoundSynthesizer>
<CsOptions>
-oCSPerformance.wav --nchnls=2 --0dbfs=1 --nodisplays --sample-rate=48000 --ksmps=10 --sample-accurate --messagelevel=70
</CsOptions>
<CsInstruments>
#include \"SetupLib.inc\"
#include \"Sounds.orc\"\n")
    (goto-char (point-max))
    (insert (concat "\nschedule 7, " end-time ", 1\n" "</CsInstruments>\n<CsScore>\nf0 "
		    end-time "\ne\n</CsScore>\n</CsoundSynthesizer>\n"))))
    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; UDP NETWORK SETUP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar cslc--csound-process nil)

(defun wsl-path (path)
  (if (and (getenv "WSL_DISTRO_NAME") (string-match "^/mnt/[a-z]" path))      
      (let ((drive-letter (concat (capitalize (substring-no-properties path 5 6)) ":")))
	(concat drive-letter (replace-regexp-in-string "/" "\\\\" (substring path 6))))
    path))

;;and back again from win format or linux format
(defun wsl-file-name-nondirectory (path)
  (file-name-nondirectory (if (string-prefix-p "/" path) path 
			    (replace-regexp-in-string "\\\\" "/" path))))


(defun cslc-settings (csdname host port cmd)
  "Prompt interface to edit and save settings.
host - address of csound server
port - The port the csound server is listening on.  
Csound command - the commandline string used to launch csound.
Default CSD - A CSD to run when Csound starts
"
  (interactive (list
		(cond ((string-empty-p cslc-init-csd)
		       (read-file-name "Set Default CSD?: " nil ""))
		      (t (setq insert-default-directory nil)
			 (read-file-name  (concat "Default CSD (" cslc-init-csd "):")  nil nil nil nil)))
		(read-string "host:" cslc-host nil nil)
		(read-number "port:" (string-to-number cslc-port))
		(read-string "Csound command:" cslc-csound-command nil nil )))
  (cond ((string-empty-p csdname) (message "CSD not set"))
	((string= " " csdname) (customize-save-variable 'cslc-init-csd "")
	 (message "CSD removed"))
        (t (customize-save-variable 'cslc-init-csd (wsl-path (file-truename csdname)))
	   (setq insert-default-directory t)
	   (message "Default CSD set to %s" (wsl-path (file-truename csdname)))))
  (unless (string= host cslc-host)
    (customize-save-variable 'cslc-host host)
    (message "setting host:%s" host))
  (when port
    (customize-save-variable 'cslc-port (number-to-string port))
    (let ((currentcmd cslc-csound-command))
      (unless (string-empty-p currentcmd)
  	(customize-save-variable 'cslc-csound-command (replace-regexp-in-string "--port=[[:digit:]]+" (concat "--port=" (number-to-string port)) currentcmd)))
      (message "port = set to %d" port)))
  (cond ((string-empty-p cmd) (message "cmd: %s" cslc-csound-command))
  	((string= " " cmd) (customize-save-variable 'cslc-csound-command "")
  	 (message "Setting empty cmd"))
  	(t (customize-save-variable 'cslc-csound-command cmd)
  	   (message "cmd: %s" cmd))))

(defun cslc-start-process ()
  "Make a process and launch Csound in a terminal"
  (interactive)
  (let ((port (string-to-number cslc-port))
	(host cslc-host)
	(csd (replace-regexp-in-string "\\\\" "\\\\\\\\" cslc-init-csd))
	(command cslc-csound-command))
    (let ((cs-process-command (concat command " " csd "\n")))
      (if (get-buffer-process "*cslc-term*")
	  (process-send-string "*cslc-term*" cs-process-command)
	(when cslc-term
	  (split-window-right)
	  (other-window 1)
	  (apply cslc-term)
	  (process-send-string "*cslc-term*" cs-process-command)))
      (unless cslc--csound-process
	(setq cslc--csound-process
	      (make-network-process :name "cslc-client" :type 'datagram :family 'ipv4 :host host :service port))))))



(defun cslc-stopcsound ()
  "Ends a csound performance and kills the process"
  (interactive)
  (process-send-string cslc--csound-process "scoreline_i \"e\"")
  (delete-process cslc--csound-process)
  (setq cslc--csound-process nil)
  (when (bufferp (get-buffer "*cslc-term*"))
    (kill-buffer "*cslc-term*")))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;PUBLIC FUNCTIONS

(defun cslc-eval-instrument ()
  "send an instrument or opcode to csound for evaluation"
  (interactive)
  (if cslc--recording (cslc--record-evaluation 'cslc-eval-instrument))
  (let ((point-now (point)))
    (save-excursion
      (let* ((beg (re-search-backward "\\(^instr \\|^opcode\s\\|^loopcode\\|^EffectConstruct\\)" nil t nil))
	     (end (re-search-forward "\\(endin\n\\|endop\n\\|}}\\)" nil t nil))
	     (endln (line-end-position))
	     (event-str (string-to-unibyte (buffer-substring-no-properties beg endln))))
	(if (or (> point-now endln) (< point-now beg))
	    (message "No code to evaluate")
	  (process-send-string cslc--csound-process event-str)      
	  ;(when *CSDOUTPUT* (csound-write-csd-output event-str))
	  (message (thing-at-point 'line))
	  (pulse-momentary-highlight-region beg endln 'highlight))))))

(defun cslc-eval-line ()
  "send a single line at point to csound for evaluation"
  (interactive)
  (if cslc--recording (cslc--record-evaluation 'cslc-eval-line))
  (save-excursion
    (let ((scline (string-to-unibyte (thing-at-point 'line))))
      (process-send-string cslc--csound-process scline)
      ;(when *CSDOUTPUT* (csound-write-csd-output scline))
      (message (thing-at-point 'line))
      (pulse-momentary-highlight-region (line-beginning-position) (line-end-position) 'highlight))))

(defun cslc-eval-region ()
  "send a region of text to csound for evaluation"
  (interactive)
  (if cslc--recording (cslc--record-evaluation 'cslc-eval-region))
  (save-excursion
    (let ((beg (region-beginning))
	  (end (region-end)))
      (let ((event-str (string-to-unibyte (buffer-substring-no-properties beg end))))
	(process-send-string cslc--csound-process event-str)
	;(when *CSDOUTPUT* (csound-write-csd-output event-str))
	(message (thing-at-point 'line))
	(pulse-momentary-highlight-region beg end 'highlight)))))

;;;;;;;;;;;;;;;;;;;;;;;;;
;;Buffer Recording
;;;;;;;;;;;;;;;;;;;;;;;;;
;;Private variables
(setq cslc--performance-start-time nil)
(defvar cslc--performance-start-time nil)
(defvar *TIMEQUEUE* nil) ;;
(setq *TIMEQUEUE* (find-file-noselect "~/*TIMEQUEUE*" t)) ;;find-file-noselect may be problematic
(defvar cslc--timequeue-point nil)

(defvar cslc--record-start-time nil)
(defvar cslc--pause-recording-clock nil)
(defvar cslc--recording-buffer-count 0)
(defvar cslc--speed 1.0)

(defvar-local cslc--recording nil)

;==================================================
;PERFORMING
;==================================================

(defun cslc--play-eval (s)
  "evaluate the item in timequeue"
  (let ((lsted (split-string (substring s 6) "#")))
    (when (and (string-suffix-p "-InDir" (buffer-name)) (buffer-local-value 'cslc--recording (buffer-base-buffer)))
      (let ((time (time-since cslc--record-start-time))
	    (action s)	    
	    (pt (point))
	    (bfr (buffer-base-buffer)))
	(with-current-buffer (get-buffer-create (concat "*" (buffer-name bfr) "-TIMEQUEUE*"))
	  (insert (format "%s " time) "|" action "|" 
		  (format "%s|%s|%s\n" pt 0 (buffer-name bfr))))))    
    (apply (read lsted) (read (cadr lsted)))))

(defun cslc--string-reverse (str)
      "Reverse the str where str is a string"
      (apply #'string 
	     (reverse 
	      (string-to-list str))))

(defun cslc--perfbuffer-name (bfname)
  "Returns a string to be used as a buffer name. Increments the 'Take' number, if a previous version of the buffer has been recorded."
  (let* ((bufname-fixed (replace-regexp-in-string "\n$" ""  bfname))
	 (ispriortake (string-match "-Take[0-9]" bufname-fixed))
	 (endbit (string-to-number (concat "9000" (cslc--string-reverse bufname-fixed))))
	 (suffix-num (number-to-string (+ 1 (string-to-number (cslc--string-reverse (substring (number-to-string endbit) 4)))))))
    (if ispriortake
	(concat (substring bufname-fixed 0 (- (length bufname-fixed)
					      (- (length (number-to-string endbit)) 4))) suffix-num)
      (concat bufname-fixed "-Take" suffix-num)
      )
    )
  )

;creates an indirect buffer. Playback happens in the indirect buffer. 
(defun cslc--get-indirect-buffer-create (basename)
  "Creates an indirect buffer. Timequeue playback happens in the indirect buffer"
  (let* ((inbufname (concat " " basename "-InDir"))
	 (buf (get-buffer inbufname)))	 
    (if buf buf (make-indirect-buffer basename inbufname t))))

(defun cslc--count-offsets-at-pt (pt)
   (let ((ohiter (heap-iter *OFFSET-HEAP*))
	 (delcount-at-pt 0)
	 (inserts-at-pt 0))
     (iter-do (offpt ohiter)
       (cond ((> offpt pt) (iter-close ohiter))
	     ((= offpt (- pt)) (setq delcount-at-pt (1+ delcount-at-pt)))	     
	     ((= offpt pt) (setq inserts-at-pt (1+ inserts-at-pt)))))
     (- inserts-at-pt delcount-at-pt)))

(defun cslc--record-buffer-offsets (beg end len)
  "At character insertion, or deletion, adds the point to the local buffer heap.
   Deletions are stored as negative points"
  (let* ((tlen (- end beg))
	 (pt beg)
	 (text (buffer-substring beg end))
	 (buf (buffer-name))
	 (indbuf (get-buffer (concat " " buf "-InDir"))))
    (with-current-buffer indbuf
      (when (cslc--ac-filter text tlen pt end len)
	(cond ((= tlen 1)
	       (heap-add *OFFSET-HEAP* pt)
	       (cslc--shift-offsets pt tlen '>=))
	      ((> tlen 1)
	       (dolist (bs (number-sequence pt (+ pt (- tlen 1))))
		 (heap-add *OFFSET-HEAP* bs))
	       (cslc--shift-offsets pt tlen '>=))
	      ((and (zerop tlen) (= len 1))
	       (heap-add *OFFSET-HEAP* (- pt))
	       (cslc--shift-offsets pt (- len) '>=)) ;pt + 1, or just pt?
	      ((and (zerop tlen) (> len 0))
	       (dolist (ds (number-sequence (+ pt (- len 1)) pt -1))
		 (heap-add *OFFSET-HEAP* (- ds)))
	       (cslc--shift-offsets (+ pt len) (- len) '>=))
	      (t (message "RBO:!!!!!!!SHOULD NOT BE HERE") '()
		 ))))))

;;calculate the offset to move the inserrt from the recorded point
(defun cslc--calc-offset (pt)
  "Reads the buffer local heap at point (pt) and calculates the tally of current deletions and insertions.
  The result is used in cslc--pollaction to displace the recorded point in timequeue"
   (let ((ohiter (heap-iter *OFFSET-HEAP*))
	 (tally 0)
	 (last -1)
	 (delcount-at-pt 0))
     (iter-do (offpt ohiter)
       (cond ((and (= (signum offpt) -1) (< (abs offpt) pt))
	      (setq tally (1- tally)))
	     ((and (= (signum offpt) -1) (= (abs offpt) pt))
	      (setq tally (1- tally))
	      (setq delcount-at-pt (1+ delcount-at-pt)))
	     ((and (= (signum offpt) -1) (> (abs offpt) pt))
	      nil)
	     ((and (< offpt pt))
	      (setq tally (1+ tally)))
	     ((= offpt pt)
	      (setq last offpt)
	      (setq tally (1+ tally))
	      )
	     ((or (= offpt (1+ last)) (= offpt last))
	      (let ((offtot (cslc--count-offsets-at-pt offpt)))
		(cond ((<= offtot 0)
		       nil)
		      (t (setq last offpt)	      
			 (setq tally (1+ tally))
			 ))))
	     ((>= offpt (+ last 2))
	      nil)
	     (t (message "calc-offset shouldn't be here pt=%s offpt=%s last=%s tally=%s" pt offpt last tally))))     
     tally))

(defun cslc--shift-offsets (pto tlen pred)
  "shift all the recorded offsets after point in the heap. "
  (let ((ofiter (heap-iter *OFFSET-HEAP*))
	(resultlist '(0)))
    (iter-do (iv ofiter)
      (when (>= (abs iv) pto) (push resultlist iv)))
    (setq resultlist (sort resultlist pred))
    (dolist (listoff resultlist)
      (heap-modify *OFFSET-HEAP* `(lambda(n)(= n ,listoff))
		   (+ listoff (* tlen (signum listoff)))))))

(defun cslc--pollaction (&optional nowtime)
  "Playback the recorded *TIMEQUEUE* performance"
  (when cslc--performance-start-time
    (with-current-buffer *TIMEQUEUE*
      (let* ((event (split-string (thing-at-point 'line) "|"))
	     (action (replace-regexp-in-string "\\^J" "\n"
					       (replace-regexp-in-string "\vert" "|" (elt event 1))))
	     (pt (string-to-number (elt event 2)))
	     (len (string-to-number (elt event 3)))
	     (destinationbuf (cslc--perfbuffer-name (elt event 4)))
	     (indirectbuf (cslc--get-indirect-buffer-create destinationbuf))
	     (now (if nowtime nowtime 0.0))
	     (next-time (progn (forward-line 1)
			       (if (eobp) nil (read (thing-at-point 'line))))))
	(with-current-buffer indirectbuf
	  (let ((pto (+ pt (cslc--calc-offset pt))))
	    ;;(message "pt|pto|diff ========== %s | %s | %s" pt pto (- pto pt))
	    (save-excursion
	      (if (< (point-max) pto) (goto-char (point-max)) (goto-char pto))
	      (cond ((not cslc--performance-start-time) (setq next-time nil))
		    ((string-prefix-p "MODE:" action)
		     (let ((mm (substring action 5)))
		       (if (not (string= major-mode mm)) 
			   (funcall (intern (substring action 5))))))
		    ((string= action "\b")
		     (delete-region pto (+ pto len))
		     (cslc--shift-offsets (+ pto len) (- len) '>=)
		     )
		    ((string-prefix-p "ELISP:" action) (cslc--play-eval action))
		    ;;((> len 0) (message "pollaction - shouldn't be here"))
		    (t
		     (insert action)
		     (cslc--shift-offsets pto (length action) '>=)
		     )))))
	(if next-time
	    (let* ((nt (float-time next-time))
		   (calctime (/ (- nt now) cslc--speed)))
	      (run-at-time
	       calctime
	       nil
	       'cslc--pollaction
	       nt
	       ))
	  (message "Finished playing *TIMEQUEUE*")
	  (setq cslc--recordingflag "Finished Playback")
	  (setq cslc--performance-start-time nil))))))

;==================================================
;RECORDING
;==================================================
(defun cslc--ac-filter (text tlen pt end len)
  "private function to ignore auto-complete shenanigans"
  (if (not (boundp 'auto-complete-mode))
      (progn (message "(not (boundp 'auto-complete)) - returning t")
	     t)
    (let* ((overlays (overlays-in (point-min) (point-max)))
	   (afterstring (when overlays
			  (let (ostring)
			    (dolist (o overlays)
			      (when (overlay-get o 'after-string) (setq ostring (overlay-get o 'after-string))))
			    ostring))))
      (cond ((and overlays (not afterstring) (> tlen 0) (string-prefix-p "\n" text))
	     (when (= end (point-max))
	       (setq-local cslc--olay-tlen tlen))
	     nil)
	    ((and (= tlen 0) (= pt (point-max)) (> cslc--olay-tlen 0))
	     (setq-local cslc--olay-tlen (- cslc--olay-tlen len))
	     nil)
	    (t
	     t)))))

(defun cslc--record-every-buffer-mod (beg end len)
  "records every change to a buffer with a timestamp in a temporary timequeue buffer.
  This function is added to after-change-functions"
  (let* ((time (time-since cslc--record-start-time))
	 (text (buffer-substring beg end))
	 (tlen (length text))
	 (pt beg)
	 (bufname (if (string-suffix-p "-InDir" (buffer-name))
		      (buffer-name (buffer-base-buffer))
		    (buffer-name))))
    (when (cslc--ac-filter text tlen pt end len)
      (setq text (replace-regexp-in-string "[\n$]" "^J" text))
      (setq text (replace-regexp-in-string "|" "\vert" text))
      (when (= tlen 0)
	(setq text "\b") (setq tlen (* len -1)))
      (save-current-buffer
	(set-buffer (get-buffer-create (concat "*" bufname "-TIMEQUEUE*")))
	(insert (format "%s " time) "|" text "|" (format "%s|%s|%s\n" pt len bufname))))))


(defun cslc--record-evaluation (funcname &rest args)
  "Records an evaluation event with timestamp in a temporary timequeue"
  (let ((time (time-since cslc--record-start-time))
	(action (format "ELISP:%S#%S" funcname args))
	(pt (point))
	(bufname (if (string-suffix-p "-InDir" (buffer-name)) (buffer-name (buffer-base-buffer)) (buffer-name))))
    ;;(message "CALLED Record-Eval in %s, writing to %s" (buffer-name) (concat "*" bufname "-TIMEQUEUE*"))
    (save-current-buffer
      (set-buffer (get-buffer-create (concat "*" bufname "-TIMEQUEUE*")))
      (insert (format "%s " time) "|" action "|" 
	      (format "%s|%s|%s\n" pt 0 bufname)))))

(defun cslc--record-mode-change (modename)
  "records a change of mode event in a timequeue"
  (let ((time (time-since cslc--record-start-time))
	(action (concat "MODE:" modename))
	(pt (point))
	(buf (buffer-name)))
    (save-current-buffer
      (set-buffer (get-buffer-create (concat "*" (buffer-name) "-TIMEQUEUE*")))
      (insert (format "%s " time) "|" action "|" 
	      (format "%s|%s|%s\n" pt 0 buf)))))


(defun cslc--record-existing-buffer-contents ()
  "records the existing change of mode event in a timequeue"
  (let ((time (time-since cslc--record-start-time))
	(text (buffer-string))
	(buf (buffer-name)))
    (setq text (replace-regexp-in-string "[\n$]" "^J" text))
    (setq text (replace-regexp-in-string "|" "\vert" text))
    (save-current-buffer
      (set-buffer (get-buffer-create (concat "*" (buffer-name) "-TIMEQUEUE*")))
      (insert (format "%s " time) "|" text "|" (format "%s|%s|%s\n" (point-min) 0 buf)))))



(defun cslc--perform-timequeue ()
  "Starts the performance. Called once at the start of a performance session."
  (unless (= (buffer-size *TIMEQUEUE*) 0)
    (with-current-buffer *TIMEQUEUE*
      (sort-numeric-fields 3 (point-min) (point-max))
      (sort-numeric-fields 2 (point-min) (point-max))
      (goto-char (point-min))
      (run-at-time (float-time (read (thing-at-point 'line)))
		   nil 'cslc--pollaction))))

;;Improve cslc--display-performance-buffers (seems crude at the moment).
;;display-buffer-alist perhaps
(defun cslc--display-performance-buffers (bufferlist)
  "Split the display into windows for each buffer recorded in *TIMEQUEUE*"
  (let ((tally 0)
	(origin-window (selected-window))
	(last-window (selected-window)))
    (dolist (buf bufferlist)
      (cond ((zerop tally)
	     (message "tally: %d | buf %s" tally buf)
	     (switch-to-buffer buf))
	    ((cl-oddp tally)
	     (message "split-v tally: %d | buf %s" tally buf)
	     (select-window (split-window-vertically))
	     (switch-to-buffer buf)
	     (setq last-window (selected-window))
	     (select-window origin-window))
	    ((cl-evenp tally) (message "split-h tally: %d | buf %s" tally buf)
	     (select-window (split-window-horizontally))	   	   
	     (switch-to-buffer buf)
	     (setq origin-window last-window)
	     (setq last-window (selected-window))
	     (select-window origin-window)
	     (setq tally (1+ tally))))
      (setq tally (1+ tally)))
    (select-window origin-window)))


(defun cslc-create-performance-buffers ()
  "Creates buffers for files specified in the timequeue.
  Each buffer is set with a local offset heap."
  (interactive)
  (let ((timequeue (find-file-noselect "~/*TIMEQUEUE*"))
	(bufnames '())
	(destnames '()))
    (with-current-buffer timequeue
      (save-excursion
	(goto-char (point-min))
	(while (not (eobp))
	  (let* ((event (split-string (thing-at-point 'line) "|"))
		 (tqbufname (replace-regexp-in-string "\n$" ""  (elt event 4))))
	    (unless (member tqbufname bufnames)	       	      
	      (let* ((destinationbufname (cslc--perfbuffer-name tqbufname))
		     (destbuf (get-buffer-create destinationbufname))
		     (indbuf (cslc--get-indirect-buffer-create destinationbufname))
		     (action (elt event 1)))
		(with-current-buffer indbuf
		  (when (string-prefix-p "MODE:" action)
		    (let ((modename (substring action 5)))
		      (unless (string= major-mode modename)
			(funcall (intern modename)))))		    
		  (unless (boundp '*OFFSET-HEAP*)
		    (message "creating *OFFSET-HEAP* in %s" (buffer-name))
		    (setq-local *OFFSET-HEAP* (make-heap '< 5000)))
		  (unless (boundp 'cslc--olay-tlen)
		    (message "creating cslc--olay-tlen in buffer %s" (buffer-name))
		    (setq-local cslc--olay-tlen 0)))
		(with-current-buffer destbuf
		  (when (string-prefix-p "MODE:" action)
		    (let ((modename (substring action 5)))
		      (unless (string= major-mode modename)
			(funcall (intern modename)))))
		  (goto-char (point-min))
		  (message "HOOK: placing cslc--record-buffer-offsets in %s" destbuf)
		  (add-hook 'after-change-functions 'cslc--record-buffer-offsets nil t))
		(push tqbufname bufnames)
		(push destinationbufname destnames))))
	  (forward-line))))
    (when (eq (count-windows) 1)
      (cslc--display-performance-buffers destnames))))


(defun cslc-play-recording ()
  "As it says on the tin. Play the recorded performance in timequeue"
  (interactive)
  (if cslc--performance-start-time
      (message "Already Performing *TIMEQUEUE*")
    (let ((ct (current-time)))
      ;;(stopwatch-start)
      (setq cslc--performance-start-time ct)
      (cslc-create-performance-buffers)
      (unless (get-buffer-process "*cslc-client*")
	(cslc-start-process))      
      (cslc--perform-timequeue)
      (message "Begun *TIMEQUEUE* Performance")
      (setq cslc--recordingflag "Begun *TIMEQUEUE* Performance"))))

(defun cslc-pause-playback ()
  "Pause the playback of the timequeue recording."
  (interactive)
  (setq cslc--performance-start-time nil)
  ;;(toggle-pause-csd-clock)
  (with-current-buffer *TIMEQUEUE*
    (beginning-of-line)
    (setq cslc--timequeue-point (point)))
  (message "%s %s" "Exiting cslc-pause-playback" cslc--timequeue-point)
  (setq cslc--recordingflag "Paused Performance"))

(defun cslc-resume-playback ()
  "Resume the performance of the timequeue recording."
  (interactive)
  (setq cslc--recordingflag "Resumed Performance Playback")  
  ;;(toggle-pause-csd-clock)
  (if (zerop (buffer-size *TIMEQUEUE*))
      (progn
	(message "%s" "*TIMEQUEUE* EMPTY - setting PST to now")
	(setq cslc--performance-start-time (current-time)))
    (with-current-buffer *TIMEQUEUE*
      (message "%s" "found something in *TIMEQUEUE")
      (goto-char cslc--timequeue-point)
      (setq cslc--performance-start-time (read (thing-at-point 'line)))
      (cslc--pollaction (float-time cslc--performance-start-time)))))

(defun cslc-start-recording ()
  "Begin recording all text changes and evaluations in the current buffer
   Changes are timestamped and stored in the *TIMEQUEUE* buffer"
  (interactive)
  (if cslc--recording
      (message "Already recording in %s" (buffer-name))
    ;;(stopwatch-start)
    (cslc-create-performance-buffers)
    (unless (boundp 'cslc--olay-tlen)
      (message "cslc-start-recording creating cslc--olay-tlen in buffer %s" (buffer-name))
      (setq-local cslc--olay-tlen 0))
    (unless cslc--performance-start-time
      (setq cslc--performance-start-time (current-time))
      (cslc--perform-timequeue))
    (unless cslc--record-start-time
      (setq cslc--record-start-time cslc--performance-start-time))
    (setq cslc--recording t)
    (cslc--record-mode-change (format "%s" major-mode))
    (unless (zerop (buffer-size))
      (cslc--record-existing-buffer-contents))
    ;;put this hook in the indirect buffer
    ;;but record in the same timequeue buffer
    (with-current-buffer (cslc--get-indirect-buffer-create (buffer-name))
      (message "adding 'cslc--record-every-buffer-mod to %s" (buffer-name))
      (add-hook 'after-change-functions
		'cslc--record-every-buffer-mod nil t))
    ;; and this as well?
    (with-current-buffer (get-buffer-create (buffer-name))
      (message "adding 'cslc--record-every-buffer-mod to %s" (buffer-name))
      (add-hook 'after-change-functions
    		'cslc--record-every-buffer-mod nil t))
    (setq cslc--recording-buffer-count (+ cslc--recording-buffer-count 1))    
    (message "RECORDING BEGUN IN %s" (buffer-name))
    (setq cslc--recordingflag "Recording Begun")))

    
(defun cslc-toggle-pause-recording ()
  "Toggle on/off recording of buffer changes"
  (interactive)
  (if (not cslc--pause-recording-clock)
      (progn
	(setq cslc--pause-recording-clock (current-time))
	(dolist (bfr (buffer-list))
	  (with-current-buffer bfr
	    (when cslc--recording
	      (remove-hook 'after-change-functions 'cslc--record-every-buffer-mod t)
	      (message "RECORDING PAUSED IN %s" (buffer-name))))))
    (setq cslc--record-start-time (time-add cslc--record-start-time (time-since cslc--pause-recording-clock)))
    (dolist (bfr (buffer-list))
      (with-current-buffer bfr
	(when cslc--recording
	  (add-hook 'after-change-functions
		    'cslc--record-every-buffer-mod nil t)
	  (message "RECORDING RESUMED IN %s" (buffer-name)))))
    (setq cslc--pause-recording-clock nil)))


(defun cslc-stop-recording ()
  "Stop recording buffer changes in timequeue.
  This also clears the local offset heap. 
  Temp timequeue buffers are merged into the main buffer
  Typically use this to finish a recording session" 
  (interactive)
  ;; (if stopwatch--timer
  ;;     (stopwatch-stop))
  (let ((clear-buffers (y-or-n-p "clear buffers?")))
    (when clear-buffers (erase-buffer))
    (dolist (bfr (buffer-list))
      (with-current-buffer bfr
	(when cslc--recording
	  (setq cslc--recording nil)
	  (remove-hook 'after-change-functions 'cslc--record-every-buffer-mod t)
	  (message "RECORDING STOPPED IN %s" (buffer-name))
	  (setq cslc--recordingflag "Recording Stopped")))
      (when (string-match-p "-TIMEQUEUE\\*\\'" (buffer-name bfr))
	(with-current-buffer bfr
	  (append-to-buffer *TIMEQUEUE* (point-min) (point-max))
	  (erase-buffer)))
      (when (string-suffix-p "-InDir" (buffer-name bfr))
	(with-current-buffer bfr
	  (when clear-buffers (erase-buffer))
	  (heap-clear *OFFSET-HEAP*))))
    (setq cslc--recording-buffer-count 0)
    (setq cslc--record-start-time nil)
    (setq cslc--performance-start-time nil)
    (setq cslc--speed 1.0)
    (with-current-buffer *TIMEQUEUE*
      (sort-numeric-fields 3 (point-min) (point-max))
      (sort-numeric-fields 2 (point-min) (point-max)) 
      )
    )
  )


;; 'string-suffix-p ... not necessary after Emacs v24.4
(if (not (fboundp 'string-suffix-p))
    (defun string-suffix-p (str1 str2 &optional ignore-case)
      (let ((begin2 (- (length str2) (length str1)))
	    (end2 (length str2)))
	(when (< begin2 0) (setq begin2 0))
	(eq t (compare-strings str1 nil nil
			       str2 begin2 end2
			       ignore-case)))))

(defun cslc-remove-recorded-session (&optional name)
  "Remove recorded entries for a particular buffer from *TIMEQUEUE*.   
  'name' is the buffer name to remove. Defaults to the name of the current buffer."
  (interactive "sBuffer name? (default is current buffer):")
  (let ((bufname (if (= (string-width name) 0)
		     (concat (buffer-name (current-buffer))"\n")
		   (concat name "\n")))
	(timequeue (find-file-noselect "~/*TIMEQUEUE*")))
    (with-current-buffer timequeue
      (let ((moreLines t))
	(goto-char 1)
	(while moreLines
	  (beginning-of-line)
	  (if (string-suffix-p bufname (thing-at-point 'line))
	      (kill-whole-line)
	    (setq moreLines (= (forward-line 1) 0))))))))


(defun cslc-timeshift-recorded-session (secs &optional name)
  "Shift timestamps of a buffer recording by n seconds"
  (interactive "sBuffer name? (default is current buffer):")
  (let ((bufname (if (= (string-width name) 0)
		     (concat (buffer-name (current-buffer))"\n")
		   (concat name "\n")))
	(timequeue (find-file-noselect "~/*TIMEQUEUE*")))
    (with-current-buffer timequeue
      (let ((moreLines t))
	(goto-char 1)
	(while moreLines
	  (beginning-of-line)
	  (if (string-suffix-p bufname (thing-at-point 'line))
	      (let ((newtime (time-add (seconds-to-time secs) (list-at-point)))
		    (timebounds (bounds-of-thing-at-point 'list)))
	        (delete-region (car timebounds) (cdr timebounds))
		(insert (format "%s" newtime))
		))
	  (setq moreLines (= (forward-line 1) 0)))))))

  
(defun cslc-set-buffer-playback-speed (speed)
  "Set the 'typing speed' for a performance. 
   Expects a number which acts as a multiplier. e.g. 1.0 = original speed. 2 = twice as fast."
  (interactive "sbuffer playback speed?:")
  (setq cslc--speed speed))

(defun cslc-increment-buffer-playback-speed ()
  "increase typing speed"
  (interactive)
  (setq cslc--speed (* cslc--speed 1.5)))

(defun cslc-decrement-buffer-playback-speed ()
  "decrease typing speed"
  (interactive)
  (setq cslc--speed (* cslc--speed (/ 1 1.5))))

(defun cslc-original-buffer-playback-speed ()
  "return to normal typing speed"
  (interactive)
  (setq cslc--speed 1.0))

;;;;;;;;;;;;;;;;;;;;
;;CSD OUTPUT - save the Performance as a Csound CSD
;; Not implemented Yet
;;;;;;;;;;;;;;;;;;;;

;;;###autoload
(define-minor-mode cslc-mode
  "Record live code performances with Csound"
  :init-value nil
  :lighter " cslc"
  :keymap (let ((map (make-sparse-keymap)))
	    (define-key map (kbd "C-c &") 'cslc-start-process)
	    (define-key map (kbd "C-c C-SPC") 'cslc-eval-instrument)
	    (define-key map (kbd "C-c ,") 'cslc-eval-region)
	    (define-key map (kbd "C-c .") 'cslc-eval-line)
	    (define-key map (kbd "C-c $") 'cslc-start-recording)
	    (define-key map (kbd "C-c %") 'cslc-stop-recording)
	    (define-key map (kbd "C-c ^") 'cslc-play-recording)
	    (define-key map (kbd "C-c C-<down>") 'cslc-next-instrument)
	    (define-key map (kbd "C-c C-<up>") 'cslc-previous-instrument)
	    map)
  (unless cslc-mode
    (let ((indbufname (concat " " (buffer-name) "-InDir")))
      (when (bufferp (get-buffer indbufname))
	(kill-buffer indbufname)))))

(defvar cslc-mode-hook nil
  "A hook for the cslc-mode.")

;; run hooks (nothing yet)
(run-hooks 'cslc-mode-hook)



;;;###autoload
(add-hook 'csound-mode-hook 'cslc-mode)

  
(provide 'cslc-mode)
;;; cslc-mode.el ends here
