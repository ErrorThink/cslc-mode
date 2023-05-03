# cslc-mode #
An Emacs minor mode for recording live code sessions with Csound

## About ##
This package provides functions which send code
to an instance of Csound running in an external terminal.
Additional features Record and play back the 'typed' live code sessions 
from multiple buffers.

### Installing ###
Download and add cslc-mode.el in your Emacs load-path.
Then add the following to your emacs init file.
`(require 'cslc-mode)
`
cslc-mode autoloads with the csound-mode major mode.

### Requirements ###

   * Csound 6.10+ 
   * Emacs 25+
   * heap.el (MELPA)
   
### Features ###

  * Launch a terminal running Csound
  * Set a default CSD to run with csound
  * Record/playback and re-record multiple live code sessions in multiple buffers.
  * Edit code within the same buffer as playback (experimental).

### Usage ###

* Launch Csound `(M-x cslc-start-process)`.
* In an empty buffer start recording `(M-x cslc-start-recording)`
* Live code your csound session. 
* When you've finished your session, stop recording `(M-x cslc-stop-recording)`.
  You may want to stop csound too `(M-x cslc-stopcsound)`.
  * Not happy with your performance?
	Remove this session from the recording `(M-x cslc-remove-recorded-session <RET>)`.
* In an new empty buffer start another recording `(M-x cslc-start-recording)`.
  Previously recorded sessions are played back in their own buffers while you record. 
* Modifying a recorded session while it's 'playing back' is also possible. 
  A numbered suffix is appended to the buffer name with '\<buffer name\>-Take[n]'.
  When finishing a new Take you may then want to delete the previous Take from *TIMEQUEUE*
`(M-x cslc-remove-recorded-session <buffer-to-remove>)
`
Performance Recordings are stored in the file **~/\*TIMEQUEUE\***
Rename and save this file for posterity. 

### Keybindings ###
* <kbd>C-c &</kbd> `cslc-start-process` start a terminal running Csound and a process to connect to it. 
* <kbd>C-c C-SPC</kbd> `cslc-eval-instrument` - Send the instrument or UDO definition to Csound 
* <kbd>C-c ,</kbd> `cslc-eval-region` - Send the selected (active) region to Csound
* <kbd>C-c .</kbd> `cslc-eval-line` - Send the line to Csound 
* <kbd>C-c $</kbd> `cslc-start-recording` - Record a performance in the buffer.
* <kbd>C-c %</kbd> `cslc-stop-recording` - Stop recording the performance (all buffers)
* <kbd>C-c ^</kbd> `cslc-play-recording` - Play a recorded performance.
* <kbd>C-c <down></kbd> `cslc-next-instrument` - Move the cursor to the next instrument in the buffer
* <kbd>C-c <up></kbd> `cslc-previous-instrument` - Move the cursor to the previous instrument in the buffer

See comment section in cslc-mode for further documentation.
