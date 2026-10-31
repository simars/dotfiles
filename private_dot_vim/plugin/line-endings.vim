" ==============================================================================
" Line Endings: flag CRLF and mixed files, and save them with LF (:Lf)
" ==============================================================================
" Shared by Vim (which loads ~/.vim/plugin itself), Neovim and LunarVim (both source this file from their config).
"
" b:line_endings describes the file on disk as last read or written: '' for LF, 'CRLF', or 'mixed' (CRLF and LF lines;
" Vim reads such a file as unix and shows ^M on the CRLF lines, so 'fileformat' alone does not reveal it). It is set
" on read, before a project's EditorConfig can switch the buffer to LF, so a CRLF file stays flagged until it is saved.
" Old Mac OS files that end lines with CR alone are read as one line and flagged as mixed; :Lf does not split them.

if exists('g:loaded_line_endings')
  finish
endif
let g:loaded_line_endings = 1

function! s:Detect() abort
  if &buftype !=# '' || &binary
    let b:line_endings = ''
  elseif &fileformat ==# 'dos'
    let b:line_endings = 'CRLF'
  else
    let b:line_endings = search('\r$', 'nw') > 0 ? 'mixed' : ''
  endif
endfunction

" Runs from a timer, so the read message ("file" 3L, 12B) does not overwrite it.
function! s:Warn(bufnr, ...) abort
  let kind = getbufvar(a:bufnr, 'line_endings', '')
  if kind !=# ''
    echohl WarningMsg
    echomsg printf('%s: %s line endings; :Lf saves it with LF', fnamemodify(bufname(a:bufnr), ':t'), kind)
    echohl None
  endif
endfunction

" Status line label: '[CRLF] ' or '[mixed] ', empty for LF.
function! LineEndings() abort
  let kind = get(b:, 'line_endings', '')
  return kind ==# '' ? '' : '[' . kind . '] '
endfunction

" Convert the buffer to LF, drop a UTF-8 byte-order mark, and write. :Lf! writes like :w!.
function! s:ToLf(bang) abort
  if !&modifiable
    echohl ErrorMsg | echomsg 'Lf: the buffer is not modifiable' | echohl None
    return
  endif
  let view = winsaveview()
  setlocal fileformat=unix nobomb
  keeppatterns keepjumps silent! %s/\r$//e
  call winrestview(view)
  execute 'write' . (a:bang ? '!' : '')
endfunction

command! -bar -bang Lf call s:ToLf(<bang>0)

augroup line_endings
  autocmd!
  " Apple's /usr/bin/vim, used on the Intel Macs, may lack +timers; it then skips only the message.
  autocmd BufReadPost * call s:Detect() | if exists('*timer_start') | call timer_start(0, function('s:Warn', [str2nr(expand('<abuf>'))])) | endif
  autocmd BufWritePost,BufNewFile * call s:Detect()
augroup END
