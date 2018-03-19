" Debugger plugin using gdb.
"
" WORK IN PROGRESS - much doesn't work yet
"
" Open two visible terminal windows:
" 1. run a pty, as with ":term NONE"
" 2. run gdb, passing the pty
" The current window is used to view source code and follows gdb.
"
" A third terminal window is hidden, it is used for communication with gdb.
"
" The communication with gdb uses GDB/MI.  See:
" https://sourceware.org/gdb/current/onlinedocs/gdb/GDB_002fMI.html
"
" Author: Bram Moolenaar
" Copyright: Vim license applies, see ":help license"

" In case this gets loaded twice.
if exists(':TermDBG')
    finish
endif

" Uncomment this line to write logging in "debuglog".
" call ch_logfile('debuglog', 'w')

" The command that starts debugging, e.g. ":TermDBG vim".
" To end type "quit" in the gdb window.
command -nargs=* -complete=file TD call s:StartDebug(<q-args>)

" Name of the gdb command, defaults to "gdb".
if !exists('g:termdbgger')
    let g:termdbgger = 'gdb'
endif
if !exists('g:termdbg_termgdb_win')
    let g:termdbg_termgdb_win = '1'
endif

let s:pc_id = 12
let s:break_id = 13
let s:stopped = 1

" if &background == 'light'
    " hi default termdbgPC term=reverse ctermbg=lightblue guibg=lightblue
" else
    " hi default termdbgPC term=reverse ctermbg=darkblue guibg=darkblue
" endif
" hi default termdbgBreakpoint term=reverse ctermbg=red guibg=red


    highlight DebugBreak guibg=darkred guifg=white ctermbg=darkred ctermfg=white
    highlight DisabledBreak guibg=lightred guifg=black ctermbg=lightred ctermfg=black

    " sign define termdbgBreakpoint linehl=DebugBreak text=B> 
    " sign define termdbgDisabledbp linehl=DisabledBreak text=b> 
    sign define termdbgBreakpoint linehl=DebugBreak text=B> texthl=DebugBreak
    sign define termdbgDisabledbp linehl=DisabledBreak text=b> texthl=DisabledBreak
    " sign define current linehl=DebugStop
    " sign define termdbgCurrent linehl=Search text=>> texthl=Search
    sign define termdbgPC linehl=MatchParen text=>> texthl=MatchParen


func s:StartDebug(cmd)
    let s:startwin = win_getid(winnr())
    let s:startsigncolumn = &signcolumn

    let s:save_columns = 0
    if exists('g:termdbg_wide')
        if &columns < g:termdbg_wide
            let s:save_columns = &columns
            let &columns = g:termdbg_wide
        endif
        let vertical = 1
    else
        let vertical = 0
    endif

    " Open a terminal window without a job, to run the debugged program
    " let s:ptybuf = term_start('NONE', {
                " \ 'term_name': 'gdb program',
                " \ 'vertical': vertical,
                " \ 'hidden': 1,
                " \ })
    " if s:ptybuf == 0
        " echoerr 'Failed to open the program terminal window'
        " return
    " endif
    " " let pty = job_info(term_getjob(s:ptybuf))['tty_out']
    " let pty = term_gettty(s:ptybuf, 0)
    " " echomsg "pty:".pty
    " if -1 == match(pty, '\\\\')
        " let pty = pty
    " else
        " " let pty= substitute(pty, '\\\\','\\', 'g')
        " let pty= substitute(pty, '\\\\','', 'g')
        " let pty= substitute(pty, '\\','/', 'g')
    " endif
    " echomsg "pty:".pty
    " let s:ptywin = win_getid(winnr())
    " if vertical
        " Assuming the source code window will get a signcolumn, use two more
        " columns for that, thus one less for the terminal window.
        " exe (&columns / 2 - 1) . "wincmd |"
    " endif

    " let cmd = [g:termdbgger, '-quiet','-q', '-f', '--interpreter=mi2','-tty', pty, a:cmd]
    let cmd = [g:termdbgger, '-quiet','-q', '-f', '--interpreter=mi2', a:cmd]
    " Create a hidden terminal window to communicate with gdb
    " \ 'hidden': 1,
    let s:commbuf = term_start(cmd, {
                \ 'term_name': 'gdb communication',
                \ 'hidden': g:termdbg_termgdb_win,
                \ 'out_cb': function('s:CommOutput'),
                \ 'exit_cb': function('s:EndDebug'),
                \ 'term_finish': 'close',
                \ })

    " if !has('patch-8.0.1261') && !has('nvim') && !s:is_win
    " call term_wait(s:commbuf, 100)
    " endif
    if s:commbuf == 0
        echoerr 'Failed to open the communication terminal window'
        exe 'bwipe! ' . s:ptybuf
        return
    endif
    let commpty = job_info(term_getjob(s:commbuf))['tty_out']

    " Open a terminal window to run the debugger.
    " Add -quiet to avoid the intro message causing a hit-enter prompt.
    " let cmd = [g:termdbgger, '-quiet', '-tty', pty, a:cmd]
    " echomsg 'executing "' . join(cmd) . '"'
    " let s:gdbbuf = term_start(cmd, {
    " \ 'exit_cb': function('s:EndDebug'),
    " \ 'term_finish': 'close',
    " \ })
    " if s:gdbbuf == 0
    " echoerr 'Failed to open the gdb terminal window'
    " exe 'bwipe! ' . s:ptybuf
    " exe 'bwipe! ' . s:commbuf
    " return
    " endif
    " let s:gdbwin = win_getid(winnr())

    " Connect gdb to the communication pty, using the GDB/MI interface
    " If you get an error "undefined command" your GDB is too old.
    " call term_sendkeys(s:gdbbuf, 'new-ui mi ' . commpty . "\r")

    " Interpret commands while the target is running.  This should usualy only be
    " exec-interrupt, since many commands don't work properly while the target is
    " running.
    call s:SendCommand('-gdb-set mi-async on')
    " call s:SendCommand('set new-console on')
    call s:SendCommand('set print pretty on')
    call s:SendCommand('set breakpoint pending on')
    call s:SendCommand('set pagination off')

    " Sign used to highlight the line where the program has stopped.
    " There can be only one.
    " sign define termdbgPC linehl=termdbgPC

    " Sign used to indicate a breakpoint.
    " Can be used multiple times.
    " sign define termdbgBreakpoint text=>> texthl=termdbgBreakpoint

    " highlight DebugBreak guibg=darkred guifg=white ctermbg=darkred ctermfg=white
    " highlight DisabledBreak guibg=lightred guifg=black ctermbg=lightred ctermfg=black

    " sign define termdbgBreakpoint linehl=DebugBreak text=B> 
    " sign define termdbgDisabledbp linehl=DisabledBreak text=b> 
    sign define termdbgBreakpoint linehl=DebugBreak text=B> texthl=DebugBreak
    sign define termdbgDisabledbp linehl=DisabledBreak text=b> texthl=DisabledBreak
    " sign define current linehl=DebugStop
    " sign define termdbgCurrent linehl=Search text=>> texthl=Search
    sign define termdbgPC linehl=MatchParen text=>> texthl=MatchParen

    " Install debugger commands in the text window.
    call win_gotoid(s:startwin)
    " call s:InstallCommands()
    " call win_gotoid(s:gdbwin)

    " Enable showing a balloon with eval info
    if has("balloon_eval") || has("balloon_eval_term")
        set bexpr=TermDBGBalloonExpr()
        if has("balloon_eval")
            set ballooneval
            set balloondelay=500
        endif
        if has("balloon_eval_term")
            set balloonevalterm
        endif
    endif

    let s:breakpoints = {}

    " augroup TermDBG
        " au BufRead * call s:BufRead()
        " au BufUnload * call s:BufUnloaded()
    " augroup END
endfunc

func s:EndDebug(job, status)
    " exe 'bwipe! ' . s:ptybuf
    exe 'bwipe! ' . s:commbuf

    let curwinid = win_getid(winnr())

    call win_gotoid(s:startwin)
    let &signcolumn = s:startsigncolumn
    call s:DeleteCommands()

    call win_gotoid(curwinid)
    if s:save_columns > 0
        let &columns = s:save_columns
    endif

    if has("balloon_eval") || has("balloon_eval_term")
        set bexpr=
        if has("balloon_eval")
            set noballooneval
        endif
        if has("balloon_eval_term")
            set noballoonevalterm
        endif
    endif

    " au! TermDBG
endfunc

let s:comm_msg = ''
" Handle a message received from gdb on the GDB/MI interface.
func s:CommOutput(chan, msg)
    " echomsg "a:msg:".a:msg

    " let msg = substitute(msg, '\r','', 'g')  "
    " let msg = substitute(msg, '\n','', 'g')  " 
    " let msg = substitute(msg, '\e','', 'g')  "
    " let msg = substitute(msg, '[?25l','', 'g')
    " let msg = substitute(msg, '[?25h','', 'g')
    let s:comm_msg .= a:msg
    let s:comm_msg = substitute(s:comm_msg, '\e[1G\|\e[44G\|\e[?25l\|\e[?25h\|\e[0K\|\e[0m\|\e[?1005l\|\e[?1000h\|\e[?1002h\|\e[?1003h\|\e[?1015h\|\e[?1006h\|\e[7G','', 'g')
    " echomsg "s:comm_msg:".s:comm_msg    

    let s:comm_msg = substitute(s:comm_msg, '\r\n&','\n\r\&', 'g')
    let s:comm_msg = substitute(s:comm_msg, '\r\n=','\n\r=', 'g')
    let s:comm_msg = substitute(s:comm_msg, '\r\n\^','\n\r\^', 'g')
    let s:comm_msg = substitute(s:comm_msg, '\r\n\~','\n\r~', 'g')
    let s:comm_msg = substitute(s:comm_msg, '\r\n(gdb)\r\n','\n\r(gdb)\n\r', 'g')
    " echomsg "s:comm_msg:".s:comm_msg    

    " let s:comm_msg = substitute(s:comm_msg, '\r\n\~','\r\~', 'g')
    " echomsg "s:comm_msg:".s:comm_msg    
    " let s:comm_msg = substitute(s:comm_msg, '\r\n=','\r=', 'g')

    " echomsg "s:comm_msg:".s:comm_msg    
    "sometimes contain 2 (gdb)

    echomsg strridx(s:comm_msg, "\n\r(gdb)\n\r")
    echomsg strpart(s:comm_msg, strlen(s:comm_msg)- strlen("\n\r(gdb)\n\r"),strlen("\n\r(gdb)\n\r"))

    if  "\n\r(gdb)\n\r" == strpart(s:comm_msg, strlen(s:comm_msg)- strlen("\n\r(gdb)\n\r"),strlen("\n\r(gdb)\n\r"))

        echomsg "msg ok!"
        " echomsg "s:comm_msg:".s:comm_msg    
        let s:comm_msg = substitute(s:comm_msg, '\r\n','', 'g')
        " echomsg "s:comm_msg:".s:comm_msg    
        let gdbmsgs = split(s:comm_msg, '\n\r(gdb)\zs')

        for gdbmsg in gdbmsgs
            " echomsg "gdbmsg:".gdbmsg
            " let lines = split(gdbmsg, '\r\n\zs')
            " let lines = split(gdbmsg, '\r\n')
            let lines = split(gdbmsg, '\n\r')
            " let lines = split(gdbmsg, '\r\n&\|\r\n\*\|\r\n=\zs')
            for line in lines
                " echomsg "line:".line
                if line =~ '^\n\r' 
                else
                    if line == "(gdb)"
                        let line = s:termdbg_prompt
                    endif

                    if line != ''
                        if line =~ '\(\*stopped\|\*running\|=thread-selected\)'
                            call s:HandleCursor(line)
                        elseif line =~ '\^done,bkpt=' || line =~ '=breakpoint-created,'
                            call s:HandleNewBreakpoint(line)
                        elseif line =~ '=breakpoint-deleted,'
                            call s:HandleBreakpointDelete(line)
                        elseif line =~ '\^done,value='
                            call s:HandleEvaluate(line)
                        elseif line =~ '\^error,msg='
                            call s:HandleError(line)
                        endif
                    endif

                    echomsg "s:mode:".s:mode
                    call s:goto_console_win()
                    call append(line("$"), line)
                    $
                    starti!
                    " stopi
                    if line =~ ':quit()'
                        return
                    endif
                    redraw
                endif
            endfor
        endfor

        " if s:mode == "i"
            " starti!
        " else
            " starti!
            " stopi
        " endif

        let s:termdbg_save_cursor = getpos(".")

        " if !s:stayInTgtWin
            " call s:goto_console_win()
            " if getline('$') != s:termdbg_prompt
                " call append('$', s:termdbg_prompt)
            " endif
            " $
            " starti!
            " " stopi
        " endif



        " if s:stayInTgtWin
            " call s:gotoTgtWin()
        " elseif s:curwin != winnr()
            " exec s:curwin."wincmd w"
        " endif

        let s:comm_msg =  '' 
    else

        " if s:mode == "i"
            " starti!
        " else
            " starti!
            " stopi
        " endif
        echomsg "Waiting for more msg to come!"
    endif

    if s:mode == "i"
        " starti!
    else
        " starti!
        stopi
    endif

    if s:stayInTgtWin
        call win_gotoid(s:startwin)
    endif

endfunc

" Install commands in the current window to control the debugger.
func s:InstallCommands_Hotkeys()
    command Break call s:SetBreakpoint()
    command Clear call s:ClearBreakpoint()
    command Step call s:SendCommand('-exec-step')
    command Over call s:SendCommand('-exec-next')
    command Finish call s:SendCommand('-exec-finish')
    command -nargs=* Run call s:Run(<q-args>)
    command -nargs=* Arguments call s:SendCommand('-exec-arguments ' . <q-args>)
    command Stop call s:SendCommand('-exec-interrupt')
    command Continue call s:SendCommand('-exec-continue')
    command -range -nargs=* Evaluate call s:Evaluate(<range>, <q-args>)
    command Gdb call win_gotoid(s:gdbwin)
    command Program call win_gotoid(s:ptywin)
    command Winbar call s:InstallWinbar()

    " TODO: can the K mapping be restored?
    nnoremap K :Evaluate<CR>

    if has('menu') && &mouse != ''
        call s:InstallWinbar()

        if !exists('g:termdbg_popup') || g:termdbg_popup != 0
            let s:saved_mousemodel = &mousemodel
            let &mousemodel = 'popup_setpos'
            an 1.200 PopUp.-SEP3-	<Nop>
            an 1.210 PopUp.Set\ breakpoint	:Break<CR>
            an 1.220 PopUp.Clear\ breakpoint	:Clear<CR>
            an 1.230 PopUp.Evaluate		:Evaluate<CR>
        endif
    endif


    " ====== syntax {{{
    highlight DebugBreak guibg=darkred guifg=white ctermbg=darkred ctermfg=white
    highlight DisabledBreak guibg=lightred guifg=black ctermbg=lightred ctermfg=black

    " sign define termdbgBreakpoint linehl=DebugBreak text=B> 
    " sign define termdbgDisabledbp linehl=DisabledBreak text=b> 
    sign define termdbgBreakpoint linehl=DebugBreak text=B> texthl=DebugBreak
    sign define termdbgDisabledbp linehl=DisabledBreak text=b> texthl=DisabledBreak
    " sign define current linehl=DebugStop
    " sign define termdbgCurrent linehl=Search text=>> texthl=Search
    sign define termdbgCurrent linehl=MatchParen text=>> texthl=MatchParen

    " highlight termdbgGoto guifg=Blue
    hi def link termdbgKey Statement
    hi def link termdbgHiLn Statement
    hi def link termdbgGoto Underlined
    hi def link termdbgPtr Underlined
    hi def link termdbgFrame LineNr
    hi def link termdbgCmd Macro
    "}}}
    " syntax
	syn keyword termdbgKey Function Breakpoint Catchpoint 
	syn match termdbgFrame /\v^#\d+ .*/ contains=termdbgGoto
	syn match termdbgGoto /\v<at [^()]+:\d+|file .+, line \d+/
	syn match termdbgCmd /^(gdb).*/
	syn match termdbgPtr /\v(^|\s+)\zs\$?\w+ \=.{-0,} 0x\w+/
	" highlight the whole line for 
	" returns for info threads | info break | finish | watchpoint
	syn match termdbgHiLn /\v^\s*(Id\s+Target Id|Num\s+Type|Value returned is|(Old|New) value =|Hardware watchpoint).*$/

	" syntax for perldb
	syn match termdbgCmd /^\s*DB<.*/
"	syn match termdbgFrame /\v^#\d+ .*/ contains=termdbgGoto
	syn match termdbgGoto /\v from file ['`].+' line \d+/
	syn match termdbgGoto /\v at ([^ ]+) line (\d+)/
	syn match termdbgGoto /\v at \(eval \d+\)..[^:]+:\d+/

	
	" shortcut in termdbg window
    inoremap <expr><buffer><BS>  TermDBG_isModifiableX() ? "\<BS>"  : ""
    inoremap <expr><buffer><c-h> TermDBG_isModifiableX() ? "\<c-h>" : ""
    noremap <buffer> <silent> i :call TermDBG_Keyi()<cr>
    noremap <buffer> <silent> I :call TermDBG_KeyI()<cr>
    noremap <buffer> <silent> a :call TermDBG_Keya()<cr>
    noremap <buffer> <silent> A :call TermDBG_KeyA()<cr>
    noremap <buffer> <silent> o :call TermDBG_Keyo()<cr>
    noremap <buffer> <silent> O :call TermDBG_Keyo()<cr>
    noremap <expr><buffer>x  TermDBG_isModifiablex() ? "x" : ""  
    noremap <expr><buffer>X  TermDBG_isModifiableX() ? "X" : ""  
    vnoremap <buffer>x ""

    noremap <expr><buffer>d  TermDBG_isModifiablex() ? "d" : ""  
    noremap <expr><buffer>u  TermDBG_isModifiablex() ? "u" : ""  
    noremap <expr><buffer>U  TermDBG_isModifiablex() ? "U" : ""  

    noremap <expr><buffer>s  TermDBG_isModifiablex() ? "s" : ""  
    noremap <buffer> <silent> S :call TermDBG_KeyS()<cr>

    noremap <expr><buffer>c  TermDBG_isModifiablex() ? "c" : ""  
    noremap <expr><buffer>C  TermDBG_isModifiablex() ? "C" : ""  

    noremap <expr><buffer>p  TermDBG_isModifiable() ? "p" : ""  
    noremap <expr><buffer>P  TermDBG_isModifiablex() ? "P" : ""  


    inoremap <expr><buffer><Del>        TermDBG_isModifiablex() ? "<Del>"    : ""  
    noremap <expr><buffer><Del>         TermDBG_isModifiablex() ? "<Del>"    : ""  
    noremap <expr><buffer><Insert>      TermDBG_isModifiableX() ? "<Insert>" : ""  

    inoremap <expr><buffer><Left>       TermDBG_isModifiableX() ? "<Left>"   : ""  
    noremap <expr><buffer><Left>        TermDBG_isModifiableX() ? "<Left>"   : ""  
    inoremap <expr><buffer><Right>      TermDBG_isModifiablex() ? "<Right>"  : ""  
    noremap <expr><buffer><Right>       TermDBG_isModifiablex() ? "<Right>"  : ""  

    inoremap <expr><buffer><Home>       "" 
    inoremap <expr><buffer><End>        ""
    inoremap <expr><buffer><Up>         ""
    inoremap <expr><buffer><Down>       ""
    inoremap <expr><buffer><S-Up>       ""
    inoremap <expr><buffer><S-Down>     ""
    inoremap <expr><buffer><S-Left>     ""
    inoremap <expr><buffer><S-Right>    ""
    inoremap <expr><buffer><C-Left>     ""
    inoremap <expr><buffer><C-Right>    ""
    inoremap <expr><buffer><PageUp>     ""
    inoremap <expr><buffer><PageDown>   ""


	noremap <buffer><silent>? :call TermDBG_toggle_help()<cr>
    " inoremap <buffer> <silent> <c-i> <c-o>:call TermDBG_gotoInput()<cr>
    " noremap <buffer> <silent> <c-i> :call TermDBG_gotoInput()<cr>

    inoremap <expr><buffer> <silent> <c-p>  "\<c-x><c-l>"
    inoremap <expr><buffer> <silent> <c-r>  "\<c-x><c-n>"

    inoremap <expr><buffer> <silent> <TAB>    pumvisible() ? "\<C-n>" : "\<c-x><c-u>"
    inoremap <expr><buffer> <silent> <S-TAB>  pumvisible() ? "\<C-p>" : "\<c-x><c-u>"
    noremap <buffer><silent> <Tab> ""
    noremap <buffer><silent> <S-Tab> ""

    noremap <buffer><silent> <ESC> :call TermDBG_close_window()<CR>

    inoremap <expr><buffer> <silent> <CR> pumvisible() ? "\<c-y><c-o>:call TermDBG(getline('.'), 'i')<cr>" : "<c-o>:call TermDBG(getline('.'), 'i')<cr>"
	imap <buffer> <silent> <2-LeftMouse> <cr>
	imap <buffer> <silent> <kEnter> <cr>

    nnoremap <buffer> <silent> <CR> :call TermDBG(getline('.'), 'n')<cr>
	nmap <buffer> <silent> <2-LeftMouse> <cr>
    imap <buffer> <silent> <LeftMouse> <Nop>
	nmap <buffer> <silent> <kEnter> <cr>

	" inoremap <buffer> <silent> <TAB> <C-X><C-L>
	"nnoremap <buffer> <silent> : <C-W>p:

	nmap <silent> <F9>	 :call TermDBG_Btoggle(0)<CR>
	nmap <silent> <C-F9>	 :call TermDBG_Btoggle(1)<CR>
	map! <silent> <F9>	 <c-o>:call TermDBG_Btoggle(0)<CR>
	map! <silent> <C-F9> <c-o>:call TermDBG_Btoggle(1)<CR>
	nmap <silent> <Leader>ju	 :call TermDBG_jump()<CR>
	nmap <silent> <C-S-F10>		 :call TermDBG_jump()<CR>
	nmap <silent> <C-F10> :call TermDBG_runToCursur()<CR>
	map! <silent> <C-S-F10>		 <c-o>:call TermDBG_jump()<CR>
	map! <silent> <C-F10> <c-o>:call TermDBG_runToCursur()<CR>
"	nmap <silent> <F6>   :call TermDBG("run")<CR>
	nmap <silent> <C-P>	 :TermDBG p <C-R><C-W><CR>
	vmap <silent> <C-P>	 y:TermDBG p <C-R>0<CR>
	nmap <silent> <Leader>pr	 :TermDBG p <C-R><C-W><CR>
	vmap <silent> <Leader>pr	 y:TermDBG p <C-R>0<CR>
	nmap <silent> <Leader>bt	 :TermDBG bt<CR>

    nmap <silent> <F5>    :TermDBG c<cr>
    nmap <silent> <S-F5>  :TermDBG k<cr>
	nmap <silent> <F10>   :TermDBG n<cr>
	nmap <silent> <F11>   :TermDBG s<cr>
	nmap <silent> <S-F11> :TermDBG finish<cr>
	nmap <silent> <c-q>   <cr>:TermDBG q<cr>

    " map! <silent> <F5>    <c-o>:TermDBG c<cr>i
    " map! <silent> <S-F5>  <c-o>:TermDBG k<cr>i
    map! <silent> <F5>    <c-o>:TermDBG c<cr>
    map! <silent> <S-F5>  <c-o>:TermDBG k<cr>
	map! <silent> <F10>   <c-o>:TermDBG n<cr>
	map! <silent> <F11>   <c-o>:TermDBG s<cr>
	map! <silent> <S-F11> <c-o>:TermDBG finish<cr>
	map! <silent> <c-q> <c-o>:TermDBG q<cr>

	amenu TermDBG.Toggle\ breakpoint<tab>F9			:call TermDBG_Btoggle(0)<CR>
	amenu TermDBG.Run/Continue<tab>F5 					:TermDBG c<CR>
	amenu TermDBG.Step\ into<tab>F11					:TermDBG s<CR>
	amenu TermDBG.Next<tab>F10							:TermDBG n<CR>
	amenu TermDBG.Step\ out<tab>Shift-F11				:TermDBG finish<CR>
	amenu TermDBG.Run\ to\ cursor<tab>Ctrl-F10			:call TermDBG_runToCursur()<CR>
	amenu TermDBG.Stop\ debugging\ (Kill)<tab>Shift-F5	:TermDBG k<CR>
	amenu TermDBG.-sep1- :

	amenu TermDBG.Show\ callstack<tab>\\bt				:call TermDBG("where")<CR>
	amenu TermDBG.Set\ next\ statement\ (Jump)<tab>Ctrl-Shift-F10\ or\ \\ju 	:call TermDBG_jump()<CR>
	amenu TermDBG.Top\ frame 						:call TermDBG("frame 0")<CR>
	amenu TermDBG.Callstack\ up 					:call TermDBG("up")<CR>
	amenu TermDBG.Callstack\ down 					:call TermDBG("down")<CR>
	amenu TermDBG.-sep2- :

	amenu TermDBG.Preview\ variable<tab>Ctrl-P		:TermDBG p <C-R><C-W><CR> 
	amenu TermDBG.Print\ variable<tab>\\pr			:TermDBG p <C-R><C-W><CR> 
	amenu TermDBG.Show\ breakpoints 				:TermDBG info breakpoints<CR>
	amenu TermDBG.Show\ locals 					:TermDBG info locals<CR>
	amenu TermDBG.Show\ args 						:TermDBG info args<CR>
	amenu TermDBG.Quit			 					:TermDBG q<CR>

	if has('balloon_eval')
		" set bexpr=TermDBG_balloonExpr()
		" set balloondelay=500
		" set ballooneval
	endif

endfunc

let s:winbar_winids = []

" Install the window toolbar in the current window.
func s:InstallWinbar()
    nnoremenu WinBar.Step   :Step<CR>
    nnoremenu WinBar.Next   :Over<CR>
    nnoremenu WinBar.Finish :Finish<CR>
    nnoremenu WinBar.Cont   :Continue<CR>
    nnoremenu WinBar.Stop   :Stop<CR>
    nnoremenu WinBar.Eval   :Evaluate<CR>
    call add(s:winbar_winids, win_getid(winnr()))
endfunc

" Delete installed debugger commands in the current window.
func s:DeleteCommands()
    delcommand Break
    delcommand Clear
    delcommand Step
    delcommand Over
    delcommand Finish
    delcommand Run
    delcommand Arguments
    delcommand Stop
    delcommand Continue
    delcommand Evaluate
    delcommand Gdb
    delcommand Program
    delcommand Winbar

    nunmap K

    if has('menu')
        " Remove the WinBar entries from all windows where it was added.
        let curwinid = win_getid(winnr())
        for winid in s:winbar_winids
            if win_gotoid(winid)
                aunmenu WinBar.Step
                aunmenu WinBar.Next
                aunmenu WinBar.Finish
                aunmenu WinBar.Cont
                aunmenu WinBar.Stop
                aunmenu WinBar.Eval
            endif
        endfor
        call win_gotoid(curwinid)
        let s:winbar_winids = []

        if exists('s:saved_mousemodel')
            let &mousemodel = s:saved_mousemodel
            unlet s:saved_mousemodel
            aunmenu PopUp.-SEP3-
            aunmenu PopUp.Set\ breakpoint
            aunmenu PopUp.Clear\ breakpoint
            aunmenu PopUp.Evaluate
        endif
    endif

    exe 'sign unplace ' . s:pc_id
    for key in keys(s:breakpoints)
        exe 'sign unplace ' . (s:break_id + key)
    endfor
    sign undefine termdbgPC
    sign undefine termdbgBreakpoint
    unlet s:breakpoints
endfunc

" :Break - Set a breakpoint at the cursor position.
func s:SetBreakpoint()
    " Setting a breakpoint may not work while the program is running.
    " Interrupt to make it work.
    let do_continue = 0
    if !s:stopped
        let do_continue = 1
        call s:SendCommand('-exec-interrupt')
        sleep 10m
    endif
    call s:SendCommand('-break-insert '
                \ . fnameescape(expand('%:p')) . ':' . line('.'))
    if do_continue
        call s:SendCommand('-exec-continue')
    endif
endfunc

" :Clear - Delete a breakpoint at the cursor position.
func s:ClearBreakpoint()
    " let fname = fnameescape(expand('%:p'))
    let fname = fnameescape(expand('%:t'))
    let fname = bufnr(fname)
    let lnum = line('.')
    for [key, val] in items(s:breakpoints)
        if val['fname'] == fname && val['lnum'] == lnum
            call term_sendkeys(s:commbuf, '-break-delete ' . key . "\r")
            " Assume this always wors, the reply is simply "^done".
            exe 'sign unplace ' . (s:break_id + key)
            unlet s:breakpoints[key]
            break
        endif
    endfor
endfunc

" :Next, :Continue, etc - send a command to gdb
func s:SendCommand(cmd)
    call term_sendkeys(s:commbuf, a:cmd . "\r")
endfunc

func s:Run(args)
    if a:args != ''
        call s:SendCommand('-exec-arguments ' . a:args)
    endif
    call s:SendCommand('-exec-run')
endfunc

func s:SendEval(expr)
    call s:SendCommand('-data-evaluate-expression "' . a:expr . '"')
    let s:evalexpr = a:expr
endfunc

" :Evaluate - evaluate what is under the cursor
func s:Evaluate(range, arg)
    if a:arg != ''
        let expr = a:arg
    elseif a:range == 2
        let pos = getcurpos()
        let reg = getreg('v', 1, 1)
        let regt = getregtype('v')
        normal! gv"vy
        let expr = @v
        call setpos('.', pos)
        call setreg('v', reg, regt)
    else
        let expr = expand('<cexpr>')
    endif
    let s:ignoreEvalError = 0
    call s:SendEval(expr)
endfunc

let s:ignoreEvalError = 0
let s:evalFromBalloonExpr = 0

" Handle the result of data-evaluate-expression
func s:HandleEvaluate(msg)
    " echomsg "HandleEvaluate:".a:msg
    let value = substitute(a:msg, '.*value="\(.*\)"', '\1', '')
    let value = substitute(value, '\\"', '"', 'g')

    if s:evalFromBalloonExpr
        if s:evalFromBalloonExprResult == ''
            let s:evalFromBalloonExprResult = s:evalexpr . ': ' . value
        else
            let s:evalFromBalloonExprResult .= ' = ' . value
        endif
        call balloon_show(s:evalFromBalloonExprResult)
    else
        echomsg '"' . s:evalexpr . '": ' . value
    endif

    if s:evalexpr[0] != '*' && value =~ '^0x' && value != '0x0' && value !~ '"$'
        " Looks like a pointer, also display what it points to.
        let s:ignoreEvalError = 1
        call s:SendEval('*' . s:evalexpr)
    else
        let s:evalFromBalloonExpr = 0
    endif
endfunc

" Show a balloon with information of the variable under the mouse pointer,
" if there is any.
func TermDBGBalloonExpr()
    if v:beval_winid != s:startwin
        return
    endif
    let s:evalFromBalloonExpr = 1
    let s:evalFromBalloonExprResult = ''
    let s:ignoreEvalError = 1
    call s:SendEval(v:beval_text)
    return ''
endfunc

" Handle an error.
func s:HandleError(msg)
    " echomsg "HandleError:".a:msg
    " call s:SendEval(v:beval_text)
    if s:ignoreEvalError
        " Result of s:SendEval() failed, ignore.
        let s:ignoreEvalError = 0
        let s:evalFromBalloonExpr = 0
        return
    endif
    echoerr substitute(a:msg, '.*msg="\(.*\)"', '\1', '')
endfunc

" Handle stopping and running message from gdb.
" Will update the sign that shows the current position.
func s:HandleCursor(msg)
    let wid = win_getid(winnr())

    if a:msg =~ '\*stopped'
        let s:stopped = 1
    elseif a:msg =~ '\*running'
        let s:stopped = 0
    endif

    " echomsg "HandleCursor:msg".a:msg
    if win_gotoid(s:startwin)
        let fname = substitute(a:msg, '.*fullname="\([^"]*\)".*', '\1', '')
        " echomsg "fname:".fname
        if -1 == match(fname, '\\\\')
            let fname = fname
        else
            let fname = substitute(fname, '\\\\','\\', 'g')
        endif
        " echomsg "fname:".fname
        if a:msg =~ '\(\*stopped\|=thread-selected\)' && filereadable(fname)
            let lnum = substitute(a:msg, '.*line="\([^"]*\)".*', '\1', '')
            if lnum =~ '^[0-9]*$'
                if expand('%:p') != fnamemodify(fname, ':p')
                    if &modified
                        " TODO: find existing window
                        exe 'split ' . fnameescape(fname)
                        let s:startwin = win_getid(winnr())
                    else
                        exe 'edit ' . fnameescape(fname)
                    endif
                endif
                " echomsg "fname:".fname
                let fname = bufnr(fname)
                " echomsg "fname:".fname
                exe lnum
                exe 'sign unplace ' . s:pc_id
                " exe 'sign place ' . s:pc_id . ' line=' . lnum . ' name=termdbgPC file=' . fname
                exe 'sign place ' . s:pc_id . ' line=' . lnum . ' name=termdbgPC buffer=' . fname
                setlocal signcolumn=yes
            endif
        else
            exe 'sign unplace ' . s:pc_id
        endif

        call win_gotoid(wid)
    endif
endfunc

" Handle setting a breakpoint
" Will update the sign that shows the breakpoint
func s:HandleNewBreakpoint(msg)
    " echomsg "HandleNewBreakpoint:".a:msg
    let nr = substitute(a:msg, '.*number="\([0-9]\)*\".*', '\1', '') + 0
    " echomsg "nr:".nr
    if nr == 0
        return
    endif

    if has_key(s:breakpoints, nr)
        let entry = s:breakpoints[nr]
    else
        let entry = {}
        let s:breakpoints[nr] = entry
    endif

    let fname = substitute(a:msg, '.*fullname="\([^"]*\)".*', '\1', '')
    let lnum = substitute(a:msg, '.*line="\([^"]*\)".*', '\1', '')

    " echomsg "fname:".fname
    " echomsg "lnum:".lnum
    if -1 == match(fname, '\\\\')
    else
        let fname = substitute(fname, '\\\\','\\', 'g')
    endif
    " echomsg "fname2:".fname

    call win_gotoid(s:startwin)
    execute 'e +'.lnum ' '.fname

    let fname = bufnr(fnamemodify(fname, ":t"))
    " let fname = bufnr(fname)

    let entry['fname'] = fname
    let entry['lnum'] = lnum

    if bufloaded(fname)
        call s:PlaceSign(nr, entry)
    endif
	redraw
endfunc

func s:PlaceSign(nr, entry)
    exe 'sign place ' . (s:break_id + a:nr) . ' line=' . a:entry['lnum'] . ' name=termdbgBreakpoint buffer=' . a:entry['fname']
    let a:entry['placed'] = 1
endfunc

" Handle deleting a breakpoint
" Will remove the sign that shows the breakpoint
func s:HandleBreakpointDelete(msg)
    let nr = substitute(a:msg, '.*id="\([0-9]*\)\".*', '\1', '') + 0
    if nr == 0
        return
    endif
    if has_key(s:breakpoints, nr)
        let entry = s:breakpoints[nr]
        if has_key(entry, 'placed')
            exe 'sign unplace ' . (s:break_id + nr)
            unlet entry['placed']
        endif
        unlet s:breakpoints[nr]
    endif
endfunc

" Handle a BufRead autocommand event: place any signs.
func s:BufRead()
    let fname = expand('<afile>:p')
    echo "s:BufRead fname:".fname
    for [nr, entry] in items(s:breakpoints)
        if entry['fname'] == fname
            call s:PlaceSign(nr, entry)
        endif
    endfor
endfunc

" Handle a BufUnloaded autocommand event: unplace any signs.
func s:BufUnloaded()
    let fname = expand('<afile>:p')
    echo "s:BufUnloaded fname:".fname
    for [nr, entry] in items(s:breakpoints)
        if entry['fname'] == fname
            let entry['placed'] = 0
        endif
    endfor
endfunc

" ======================================================================================
" Prevent multiple loading unless: let force_load=1

let s:ismswin=has('win32')

" ====== config {{{
let s:termdbg_winheight = 15
let s:termdbg_bufname = "__TermDBG__"
let s:termdbg_prompt = '(gdb) '
let s:dbg = 'gdb'
let g:termdbg_exrc = $HOME.'/termdbg_exrc'

let s:perldbPromptRE = '^\s*DB<\+\d\+>\+\s*'

" used by system-call style
" used by libcall style
"}}}
" ====== global {{{
let s:bplist = {} " id => {file, line, disabled} that returned by gdb

let s:gdbd_port = 30777 
let s:termdbg_running = 0
let s:debugging = 0
" for pathfix
let s:unresolved_bplist = {} " elem: file_basename => %bplist
"let s:pathMap = {} " unresolved_path => fullpath
let s:nameMap = {} " file_basename => {fullname, pathFixed=0|1}, set by s:getFixedPath()

let s:completers = []
let s:historys = []

"let g:termdbg_perl = 0

let s:set_disabled_bp = 0
"}}}
    " ====== syntax {{{
    highlight DebugBreak guibg=darkred guifg=white ctermbg=darkred ctermfg=white
    highlight DisabledBreak guibg=lightred guifg=black ctermbg=lightred ctermfg=black

    " sign define termdbgBreakpoint linehl=DebugBreak text=B> 
    " sign define termdbgDisabledbp linehl=DisabledBreak text=b> 
    sign define termdbgBreakpoint linehl=DebugBreak text=B> texthl=DebugBreak
    sign define termdbgDisabledbp linehl=DisabledBreak text=b> texthl=DisabledBreak
    " sign define current linehl=DebugStop
    " sign define termdbgCurrent linehl=Search text=>> texthl=Search
    sign define termdbgCurrent linehl=MatchParen text=>> texthl=MatchParen

    " highlight termdbgGoto guifg=Blue
    hi def link termdbgKey Statement
    hi def link termdbgHiLn Statement
    hi def link termdbgGoto Underlined
    hi def link termdbgPtr Underlined
    hi def link termdbgFrame LineNr
    hi def link termdbgCmd Macro
    "}}}
" ====== toolkit {{{
let s:match = []
function! s:mymatch(expr, pat)
	let s:match = matchlist(a:expr, a:pat)
	return len(s:match) >0
endf

function! s:dirname(file)
	if s:ismswin
		let pos = strridx(a:file, '\')
	else
		let pos = strridx(a:file, '/')
	endif
	return strpart(a:file, 0, pos)
endf

function! s:basename(file)
"	let f = substitute(file, '\', '/', 'g')
	let pos = strridx(a:file, '/')
	if pos<0 && s:ismswin
		let pos = strridx(a:file, '\')
	endif
	return strpart(a:file, pos+1)
endf
"}}}
" ====== app toolkit {{{
function! s:goto_console_win()
	if bufname("%") == s:termdbg_bufname
		return
	endif
	let termdbg_winnr = bufwinnr(s:termdbg_bufname)
	if termdbg_winnr == -1
		" if multi-tab or the buffer is hidden
		call TermDBG_openWindow()
		let termdbg_winnr = bufwinnr(s:termdbg_bufname)
	endif
	exec termdbg_winnr . "wincmd w"
endf
" go to edit buffer ?
function! s:gotoTgtWin()
	let termdbg_winnr = bufwinnr(s:termdbg_bufname)
	if winnr() == termdbg_winnr
        exec "wincmd k"
	endif
endf

function! s:TermDBG_bpkey(file, line)
	return a:file . ":" . a:line
endf

function! s:TermDBG_curpos()
	" ???? filename ????
	let file = expand("%:t")
	let line = line(".")
	return s:TermDBG_bpkey(file, line)
endf

function! s:placebp(id, line, bnr, disabled)
	let name = (!a:disabled)? "termdbgBreakpoint": "termdbgDisabledbp"
	execute "sign place " . a:id . " name=" . name . " line=" . a:line. " buffer=" . a:bnr
endf

function! s:unplacebp(id)
	execute "sign unplace ". a:id
endf

function! s:setbp(file, lineno, disabled)
	if a:file == "" || a:lineno == 0
		let key = s:TermDBG_curpos()
	else
		let key = s:TermDBG_bpkey(a:file, a:lineno)
	endif
	let s:set_disabled_bp = a:disabled
	call TermDBG("break ".key)
	let s:set_disabled_bp = 0
	" will auto call back s:TermDBG_cb_setbp
endf

function! s:delbp(id)
	call TermDBG("delete ".a:id)
	call s:TermDBG_cb_delbp(a:id)
" 	call TermDBG("clear ".key)
endf

"}}}

" ====== functions {{{
" Get ready for communication
function! TermDBG_openWindow()
    let bufnum = bufnr(s:termdbg_bufname)

    if bufnum == -1
        " Create a new buffer
        let wcmd = s:termdbg_bufname
    else
        " Edit the existing buffer
        let wcmd = '+buffer' . bufnum
    endif

    " Create the tag explorer window
    exe 'silent!  botright ' . s:termdbg_winheight . 'split ' . wcmd
    if line('$') <= 1 && g:termdbg_enable_help
        silent call append ( 0, s:help_text )
    endif
    call s:InstallWinbar()
endfunction

" NOTE: this function will be called by termdbg script.
function! TermDBG_open()
	" save current setting and restore when termdbg quits via 'so .exrc'
	" exec 'mk! '
    exec 'mk! ' . g:termdbg_exrc . s:gdbd_port
    "delete line set runtimepath for missing some functions after termdbg quit
    silent exec '!start /b sed -i "/set runtimepath/d" ' . g:termdbg_exrc . s:gdbd_port
    let sed_tmp = fnamemodify(g:termdbg_exrc . s:gdbd_port, ":p:h")
    silent exec '!start /b rm -f '. sed_tmp . '/sed*'   

	set nocursorline
	set nocursorcolumn

	call TermDBG_openWindow()

    " Mark the buffer as a scratch buffer
    setlocal buftype=nofile
    " We need buffer content hold
    " setlocal bufhidden=delete
    "i mode disable mouse
    setlocal mouse=nvch
    setlocal complete=.
    setlocal noswapfile
    setlocal nowrap
    setlocal nobuflisted
    setlocal nonumber
	setlocal winfixheight
	setlocal cursorline

	setlocal foldcolumn=2
	setlocal foldtext=TermDBG_foldTextExpr()
	setlocal foldmarker={,}
	setlocal foldmethod=marker

    augroup TermDBGAutoCommand
"	autocmd WinEnter <buffer> if line(".")==line("$") | starti | endif
	" autocmd WinLeave <buffer> stopi
	" autocmd BufUnload <buffer> call s:TermDBG_bufunload()
    augroup end

	" call s:TermDBG_shortcuts()
    call s:InstallCommands_Hotkeys()
	
	let s:termdbg_running = 1

    " call TermDBG("init") " get init msg
    " call TermDBG("help") " get init msg
    call TermDBG("") " get init msg
    starti!
    " call cursor(0, 7)
	
    setl completefunc=TermDBG_Complete
	"wincmd p
endfunction

function! s:TermDBG_bufunload()
	if s:termdbg_running
		call TermDBG('q')
	else
		call s:TermDBG_cb_close()
	endif
endfunction

function! s:TermDBG_goto(file, line)
	let f = s:getFixedPath(a:file)
	if strlen(f) == 0 
		return
	endif
	call s:gotoTgtWin()
	if bufnr(f) != bufnr("%")
		if &modified || bufname("%") == s:termdbg_bufname
			execute 'new '.f
		else
			execute 'e '.f
		endif

		" resolve bp when entering new buffer
		let base = s:basename(a:file)
		if has_key(s:unresolved_bplist, base)
			let bplist = s:unresolved_bplist[base]
			for [id, bp] in items(bplist)
				call s:TermDBG_cb_setbp(id, bp.file, bp.line)
			endfor
			unlet s:unresolved_bplist[base]
		endif
	endif

	execute a:line
	if has('folding')
		silent! foldopen!
	endif
	redraw
"  	call winline()
endf

function! s:getFixedPath(file)
	if ! filereadable(a:file)
		let base = s:basename(a:file)
		if has_key(s:nameMap, base) 
			return s:nameMap[base]
		endif
		if base == expand("%:t")
			let s:nameMap[base] = expand("%:p")
			return s:nameMap[base]
		endif
		let nr = bufnr(base)
		if nr != -1
			let s:nameMap[base] = bufname(nr)
			return s:nameMap[base]
		endif
		return ""
	endif
	return a:file
endf

" breakpoint highlight line may move after you edit the file. 
" this function re-set such BPs (except disables ones) that don't match the actual line.
function! s:refreshBP()
	" get sign list
	lan message C
	redir => a
	sign place
	redir end

" e.g.
" 	Signs for cpp1.cpp:
" 		line=71  id=1  name=disabledbp
" 		line=73  id=1  name=disabledbp
" 	Signs for /usr/share/vim/current/doc/eval.txt:
" 		line=4  id=1  name=bp1

	let confirmed = 0
	for line in split(a, "\n")
		if s:mymatch(line, '\v\s+line\=(\d+)\s+id\=(\d+)') && has_key(s:bplist, s:match[2])
			let lineno = s:match[1]
			let id = s:match[2]
			let bp = s:bplist[id]
			if bp.line != lineno
				if !confirmed 
					let choice = confirm("Breakpoint position changes. Refresh now? (Choose No if the source code does not match the executable.)", "&Yes\n&No")
					if choice != 1
						break
					endif
					let confirmed = 1
				endif
				call s:delbp(id)
				call s:setbp(bp.file, lineno, bp.disabled)
			endif
		endif
	endfor
endf

function! s:setDebugging(val)
	if s:debugging != a:val
		if s:debugging == 0  " 0 -> 1: run/attach
			call s:refreshBP()
		endif
		let s:debugging = a:val
	endif
endf

"====== callback {{{
let s:callmap={ 
	\'setdbg': 's:setdbg', 
	\'setbp': 's:TermDBG_cb_setbp', 
	\'delbp': 's:TermDBG_cb_delbp', 
	\'setpos': 's:TermDBG_cb_setpos', 
	\'delpos': 's:TermDBG_cb_delpos', 
	\'exe': 's:TermDBG_cb_exe', 
	\'quit': 's:TermDBG_cb_close' 
\ }

function! s:setdbg(dbg)
	let s:dbg = a:dbg
	if s:dbg == "perldb"
		let s:termdbg_prompt = "  DB<1> "
	elseif s:dbg == 'gdb'
		let s:termdbg_prompt = "(gdb) "
	endif
endf

function! s:TermDBG_cb_setbp(id, file, line, ...)
	if has_key(s:bplist, a:id)
		return
	endif
	let hint = a:0>0 ? a:1 : ''
	let bp = {'file': a:file, 'line': a:line, 'disabled': s:set_disabled_bp}
	let f = s:getFixedPath(a:file)
	if (hint == 'pending' && bufnr(a:file) == -1) || strlen(f)==0
		let base = s:basename(a:file)
		if !has_key(s:unresolved_bplist, base)
			let s:unresolved_bplist[base] = {}
		endif
		let bplist = s:unresolved_bplist[base]
		let bplist[a:id] = bp
		return
	endif
	call s:TermDBG_goto(f, a:line)
"	execute "sign unplace ". a:id
	if bp.disabled
		call TermDBG("disable ".a:id)
	endif
	call s:placebp(a:id, a:line, bufnr(f), bp.disabled)
	let s:bplist[a:id] = bp
endfunction

function! s:TermDBG_cb_delbp(id)
	if has_key(s:bplist, a:id)
		unlet s:bplist[a:id]
		call s:unplacebp(a:id)
	endif
endf

let s:last_id = 0
function! s:TermDBG_cb_setpos(file, line)
	if a:line <= 0
		call s:setDebugging(1)
		return
	endif

	let s:nameMap[s:basename(a:file)] = a:file
	call s:TermDBG_goto(a:file, a:line)
	call s:setDebugging(1)

	" place the next line before unplacing the previous 
	" otherwise display will jump
	let newid = (s:last_id+1) % 2
	execute "sign place " .  (10000+newid) ." name=termdbgCurrent line=".a:line." buffer=".bufnr(a:file)
	execute "sign unplace ". (10000+s:last_id)
	let s:last_id = newid
endf

function! s:TermDBG_cb_delpos()
	execute "sign unplace ". (10000+s:last_id)
	call s:setDebugging(0)
endf

function! s:TermDBG_cb_exe(cmd)
	exe a:cmd
endf

function! s:TermDBG_cb_close()
	if !s:termdbg_running
		return
	endif

	let s:termdbg_running = 0
	let s:bplist = {}
	let s:unresolved_bplist = {}
	sign unplace *
	if has('balloon_eval')
		set bexpr&
	endif

	" If gdb window is open then close it.
    call s:goto_console_win()
    quit

    silent! autocmd! TermDBGAutoCommand
    " 这里为什么要mapclear,想去掉termdbg加入的map
    " mapclear 
    " mapclear!
    " 用mapclear不合理,改为逐个unmap

	unmap <F9>
	unmap <C-F9>
	unmap <Leader>ju
	unmap <C-S-F10>
	unmap <C-F10>
	unmap <C-P>
	unmap <Leader>pr
	unmap <Leader>bt

	unmap <F5>
	unmap <S-F5>
	unmap <F10>
	unmap <F11>
	unmap <S-F11>
	unmap <c-q>

	if s:ismswin
        " so _exrc
        exec 'so '. g:termdbg_exrc . s:gdbd_port
        call delete(g:termdbg_exrc . s:gdbd_port)
	else
        " so .exrc
        exec 'so '. g:termdbg_exrc . s:gdbd_port
        call delete(g:termdbg_exrc . s:gdbd_port)
	endif
endf

"}}}

function! TermDBG_call(cmd)
	let usercmd = a:cmd
    call add(s:historys, usercmd)

    echomsg "usercmd:".usercmd

    call s:SendCommand(a:cmd)
    return ''

endf

" mode: i|n|c|<empty>
" i - input command in VGDB window and press enter
" n - press enter (or double click) in VGDB window
" c - run Gdb command
function! TermDBG(cmd, ...)  " [mode]
	let usercmd = a:cmd
    let s:mode = a:0>0 ? a:1 : ''
    if usercmd == ""
        let s:mode = 'i'
    endif
    " echomsg "s:mode:".s:mode
    " let s:mode = mode()
    " echomsg this first time cursor pos wrong
    " echomsg "s:mode:".s:mode

	if s:termdbg_running == 0
        let s:gdbd_port= 30000 + reltime()[1] % 10000
        call s:StartDebug(usercmd)
		call TermDBG_open()

		return
	endif

	if s:termdbg_running == 0
		echomsg "termdbg is not running"
		return
	endif

    if -1 == bufwinnr(s:termdbg_bufname)
        call TermDBG_toggle_window()
        return
    endif

	let s:curwin = winnr()
    if s:curwin == bufwinnr(s:termdbg_bufname)
        let s:stayInTgtWin = 0
    else
        let s:stayInTgtWin = 1
    endif

	if s:dbg == 'gdb' && usercmd =~ '^\s*(gdb)' 
		let usercmd = substitute(usercmd, '^\s*(gdb)\s*', '', '')
    "elseif s:mode == 'i'
    "    " trim left and clean the search word
    "    s/^\s\+//e
    "    let @/=''
    "    if line('.') != line('$')
    "        call append('$', s:termdbg_prompt . usercmd)
    "        $
    "    else
    "        exe "normal I" . s:termdbg_prompt
    "    endif
	endif
	"" goto frame
	"" 	i br (info breakpoints)
	"" 	#0  0x00007fc54f6955e7 in recv () from /lib64/libpthread.so.0
	"if s:mymatch(usercmd, '\v^#(\d+)') && s:debugging
	"	let usercmd = "@frame " . s:match[1]
	"	let s:stayInTgtWin = 1
	"	let s:mode = 'n'
	"
	"" goto thread and show frames
	"" 	i thr (info threads)
	"" 	7    Thread 0x7fc54032b700 (LWP 25787) "java" 0x00007fc54f6955e7 in recv () from /lib64/libpthread.so.0
	"elseif s:mymatch(usercmd, '\v^\s+(\d+)\s+Thread ') && s:debugging
	"	let usercmd = "@thread " . s:match[1] . "; bt"

	"" Breakpoint 1, TmScrParser::Parse (this=0x7fffffffbbb0) at ../../BuildBuilder/CreatorDll/TmScrParser.cpp:64
	"" Breakpoint 14 at 0x7ffff7bbeec1: file ../../BuildBuilder/CreatorDll/RDLL_SboP.cpp, line 111.
	"" Breakpoint 6 (/home/builder/depot/BUSMB_B1/SBO/9.01_DEV/BuildBuilder/CreatorDll/RDLL_SboP.cpp:92) pending.
	"" Breakpoint 17 at 0x7fc3f1f8b523: B1FileWriter.cpp:268. (2 locations)
	"elseif s:mymatch(usercmd, '\v<at %(0x\S+ )?(..[^:]*):(\d+)') || s:mymatch(usercmd, '\vfile ([^,]+), line (\d+)') || s:mymatch(usercmd, '\v\((..[^:]*):(\d+)\)')
	"	call s:TermDBG_goto(s:match[1], s:match[2])
	"	return
	"" for perldb:
	""   @ = main::getElems(...) called from file `./parse_vc10.pl' line 207
	"" Note: On windows: perldb uses "'" rather than "`"
	"" 	DB::eval called at /usr/lib/perl5/5.10.0/perl5db.pl line 3436
	""   syntax error at (eval 9)[C:/Perl/lib/perl5db.pl:646] line 2, near "frame 0"
	"elseif s:mymatch(usercmd, '\v from file [`'']([^'']+)'' line (\d+)') || s:mymatch(usercmd, '\v at ([^ ]+) line (\d+)') || s:mymatch(usercmd, '\v at \(eval \d+\)(..[^:]+):(\d+)')
	"	call s:TermDBG_goto(s:match[1], s:match[2])
	"	return
	"elseif s:mode == 'n'  " mode n: jump to source or current callstack, dont exec other gdb commands
	"	call TermDBG_expandPointerExpr()
	"	return
	"endif

    "call s:goto_console_win()
    "if getline("$") =~ '^\s*$'
    "    $delete
    "endif

    call TermDBG_call(usercmd)

    " for line in lines
        " let hideline = 0
        " if line =~ '^vi:'
            " let cmd = substitute(line, '\v^vi:(\w+)', '\=s:callmap[submatch(1)]', "")
            " let hideline = 1
            " " echomsg cmd
            " exec 'call ' . cmd
            " if line =~ ':quit()'
                " return
            " endif
        " endif
        " if !hideline
            " call s:goto_console_win()
            " " bugfix: '{0x123}' is wrong treated when foldmethod=marker 
            " let line = substitute(line, '{\ze\S', '{ ', 'g')
            " call append(line("$"), line)
            " $
            " starti!
            " " stopi
            " if line =~ ':quit()'
                " return
            " endif
            " redraw
            " "let output_{out_count} = substitute(line, "", "", "g")
        " endif
    " endfor
    " if s:dbg == 'perldb' && line =~ s:perldbPromptRE
        " let s:termdbg_prompt = line
    " endif

    " if mode == 'i' && !stayInTgtWin
        " call s:goto_console_win()
        " if getline('$') != s:termdbg_prompt
            " call append('$', s:termdbg_prompt)
        " endif
        " $
        " starti!
    " endif

    " if stayInTgtWin
        " call s:gotoTgtWin()
    " elseif curwin != winnr()
        " exec curwin."wincmd w"
    " endif

    " let s:termdbg_save_cursor = getpos(".")

endf

function TermDBG_toggle_window()
    if  s:termdbg_running == 0
        return
    endif
    let result = TermDBG_close_window()
    if result == 0
        call s:goto_console_win()
        call setpos('.', s:termdbg_save_cursor)
    endif
endfunction

function TermDBG_close_window()
    let winnr = bufwinnr(s:termdbg_bufname)
    if winnr != -1
        call s:goto_console_win()
        let s:termdbg_save_cursor = getpos(".")
        close
        return 1
    endif
    return 0
endfunction



" Toggle breakpoints
function! TermDBG_Btoggle(forDisable)
	call s:gotoTgtWin()
	let file = expand("%:t")
	let line = line('.')
	for [id, bp] in items(s:bplist)
		if bp.line == line && s:basename(bp.file) == file
			if ! a:forDisable
				call s:delbp(id)
			else
				if bp.disabled
					call TermDBG("enable ".id)
				else
					call TermDBG("disable ".id)
				endif
				let bp.disabled = !bp.disabled
				call s:placebp(id, bp.line, bufnr("%"), bp.disabled)
			endif
			return
		endif
	endfor
	if ! a:forDisable
		call s:setbp('', 0, 0) " set on current position
	endif
endf

function! TermDBG_jump()
	call s:gotoTgtWin()
	let key = s:TermDBG_curpos()
"	call TermDBG("@tb ".key." ; ju ".key)
"	call TermDBG("set $rbp1=$rbp; set $rsp1=$rsp; @tb ".key." ; ju ".key . "; set $rsp=$rsp1; set $rbp=$rbp1")
	call TermDBG(".ju ".key)
endf

function! TermDBG_runToCursur()
	call s:gotoTgtWin()
	let key = s:TermDBG_curpos()
	call TermDBG("@tb ".key." ; c")
endf

function! TermDBG_isPrompt()
    if  strpart(s:termdbg_prompt, 0, 5) == strpart(getline("."), 0, 5) && col(".") <= strlen(s:termdbg_prompt)+1 
        return 1
    else
        return 0
    endif
endf

function! TermDBG_isModifiable()
    let pos = getpos(".")  
    let curline = pos[1]
    if  curline == line("$") && strpart(s:termdbg_prompt, 0, 5) == strpart(getline("."), 0, 5) && col(".") >= strlen(s:termdbg_prompt)
        return 1
    else
        return 0
    endif
endf

function! TermDBG_isModifiablex()
    let pos = getpos(".")  
    let curline = pos[1]
    if  curline == line("$") && strpart(s:termdbg_prompt, 0, 5) == strpart(getline("."), 0, 5) && col(".") >= strlen(s:termdbg_prompt)+1
        return 1
    else
        return 0
    endif
endf
function! TermDBG_isModifiableX()
    let pos = getpos(".")  
    let curline = pos[1]
    if  curline == line("$") && strpart(s:termdbg_prompt, 0, 5) == strpart(getline("."), 0, 5) && col(".") >= strlen(s:termdbg_prompt)+2
        return 1
    else
        return 0
    endif
endf
fun! TermDBG_Keyi()
    let pos = getpos(".")  
    let curline = pos[1]
    let curcol = pos[2]
    if curline == line("$")
        if curcol >  strlen(s:termdbg_prompt)
            starti
        else
            starti!
        endif
    else
        silent call TermDBG_gotoInput()
    endif
endf

fun! TermDBG_KeyI()
    let pos = getpos(".")  
    let curline = pos[1]
    let curcol = pos[2]
    if curline == line("$")
        let pos[2] = strlen(s:termdbg_prompt)+1
        call setpos(".", pos)
        starti
    else
        silent call TermDBG_gotoInput()
    endif
endf

fun! TermDBG_Keya()
    let linecon = getline("$")
    let pos = getpos(".")  
    let curline = pos[1]
    let curcol = pos[2]
    if curline == line("$")
        if curcol >=  strlen(s:termdbg_prompt)
            if linecon == s:termdbg_prompt
                starti!
            else
                let pos[2] = pos[2]+1
                call setpos(".", pos)
                if pos[2] == col("$") 
                    starti!
                else
                    starti
                endif
            endif
        else
            starti!
        endif
    else
        silent call TermDBG_gotoInput()
    endif
endf

fun! TermDBG_KeyA()
    let pos = getpos(".")  
    let curline = pos[1]
    let curcol = pos[2]
    if curline == line("$")
        starti!
    else
        silent call TermDBG_gotoInput()
    endif
endf

function TermDBG_Keyo()
    let linecon = getline("$")
    if linecon == s:termdbg_prompt
        exec "normal G"
        starti!
    else
        call append('$', s:termdbg_prompt)
        $
        starti!
    endif
endfunction

function TermDBG_KeyS()
    exec "normal G"
    exec "normal dd"
    call append('$', s:termdbg_prompt)
    $
	starti!
endfunction


function! s:TermDBG_shortcuts()
endf

function! TermDBG_balloonExpr()
	return TermDBG_call('.p '.v:beval_text)
" 	return 'Cursor is at line ' . v:beval_lnum .
" 		\', column ' . v:beval_col .
" 		\ ' of file ' .  bufname(v:beval_bufnr) .
" 		\ ' on word "' . v:beval_text . '"'
endf

function! TermDBG_foldTextExpr()
	return getline(v:foldstart) . ' ' . substitute(getline(v:foldstart+1), '\v^\s+', '', '') . ' ... (' . (v:foldend-v:foldstart-1) . ' lines)'
endfunction

" if the value is a pointer ( var = 0x...), expand it by "TermDBG p *var"
" e.g. $11 = (CDBMEnv *) 0x387f6d0
" e.g.  
" (CDBMEnv) $22 = {
"  m_pTempTables = 0x37c6830,
"  ...
" }
function! TermDBG_expandPointerExpr()
	if ! s:mymatch(getline('.'), '\v((\$|\w)+) \=.{-0,} 0x')
		return 0
	endif
	let cmd = s:match[1]
	let lastln = line('.')
	while 1
		normal [z
		if line('.') == lastln
			break
		endif
		let lastln = line('.')

		if ! s:mymatch(getline('.'), '\v(([<>$]|\w)+) \=')
			return 0
		endif
		" '<...>' means the base class. Just ignore it. Example:
" (OBserverDBMCInterface) $4 = {
"   <__DBMC_ObserverA> = {
"     members of __DBMC_ObserverA:
"     m_pEnv = 0x378de60
"   }, <No data fields>}

		if s:match[1][0:0] != '<' 
			let cmd = s:match[1] . '.' . cmd
		endif
	endwhile 
"	call append('$', cmd)
	exec "TermDBG p *" . cmd
	if foldlevel('.') > 0
		" goto beginning of the fold and close it
		normal [zzc
		" ensure all folds for this var are closed
		foldclose!
	endif
	return 1
endf
"}}}

let s:help_open = 0
let s:help_text_short = [
			\ '" Press ? for help',
			\ '',
			\ ]

let s:help_text = s:help_text_short

" s:update_help_text {{{2
function s:update_help_text()
    if s:help_open
        let s:help_text = [
            \ '<F5> 	- run or continue (.c)',
            \ '<S-F5> 	- stop debugging (kill)',
            \ '<F10> 	- next',
            \ '<F11> 	- step into',
            \ '<S-F11> - step out (finish)',
            \ '<C-F10>	- run to cursor (tb and c)',
            \ '<F9> 	- toggle breakpoint on current line',
            \ '<C-F9> 	- toggle enable/disable breakpoint on current line',
            \ '\ju or <C-S-F10> - set next statement (tb and jump)',
            \ '<C-P>   - view variable under the cursor (.p)',
            \ '<TAB>   - trigger complete ',
            \ ]
    else
        let s:help_text = s:help_text_short
    endif
endfunction
if !exists('g:termdbg_enable_help')
    let g:termdbg_enable_help = 1
endif

function TermDBG_toggle_help()
	if !g:termdbg_enable_help
		return
	endif

    let s:help_open = !s:help_open
    silent exec '1,' . len(s:help_text) . 'd _'
    call s:update_help_text()
    silent call append ( 0, s:help_text )
    silent keepjumps normal! gg
endfunction

function TermDBG_gotoInput()
    " exec "InsertLeave"
    exec "normal G"
	starti!
endfunction

fun! TermDBG_Complete(findstart, base)

    if a:findstart

        let usercmd = getline('.')
        if s:dbg == 'gdb' && usercmd =~ '^\s*(gdb)' 
            let usercmd = substitute(usercmd, '^\s*(gdb)\s*', '', '')
            let usercmd = substitute(usercmd, '*', '', '') "fixed *pointer
            let usercmd = 'complete ' .  usercmd
        endif
        " echomsg "usercmd:".usercmd
        let s:completers = split(TermDBG_call(usercmd), "\n")
        " for ct in (s:completers)
            " echomsg 'ct:'.ct
        " endfor

        " locate the start of the word
        let line = getline('.')
        let start = col('.') - 1
        while start > 0 && line[start - 1] =~ '\S' && line[start-1] != '*' "fixed *pointer
            let start -= 1
        endwhile
        return start
    else
        " find s:completers matching the "a:base"
        let res = []
        " for m in split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec") 
        for m in (s:completers)
            " echomsg 'm:'m
            " echomsg 'a:base:'. a:base .'='
            if a:base == '' 
                return res
            endif

            if m =~ '^' . a:base
                call add(res, m)
                " echomsg 'm1:'m
            endif

            if m =~ '^\a\+\s\+' . a:base
                call add(res, substitute(m, '^\a*\s*', '', ''))
                " echomsg 'm2:'m
            endif
        endfor
        " for r in res
            " echomsg r
        " endfor
        return res
    endif
endfun

" ====== commands {{{
command! -nargs=* -complete=file TermDBG :call TermDBG(<q-args>)
" ca gdb TermDBG
" ca Gdb TermDBG
" directly show result; must run after TermDBG is running
command! -nargs=* -complete=file TermDBGcall :echo TermDBG_call(<q-args>)
"}}}
" vim: set foldmethod=marker :


