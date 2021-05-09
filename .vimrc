" =-=-=-=-=-=-=-=-=-=-=-=- FILE START -=-=-=-=-=-=-=-=-=-=-=-= "



" =-=-=-=-=-=-=-= Vim Config (Mostly for NVim) =-=-=-=-=-=-=-= "
" =-=-=-=-=-=-=-=-=-=- By: Joshua Pelealu -=-=-=-=-=-=-=-=-=-= "



" =-=-=-=-=-=-=-=-= File Formatting Guideline -=-=-=-=-=-=-=-= "

    " =-=-=-=-=-=-=-=-=-=-=-=-=-= ---- =-=-=-=-=-=-=-=-=-=-=-=-=-= "
    "                                                              "
    "                                                              "
    " 1. Always start a block of related subjects in between two   "
    "    seperator blocks with identifiers centered and make sure  "
    "    to indent them accordingly                                "
    "                                                              "
    " 2. Always use the block seperator below to seperate blocks   "
    "    with 2 spaces in between the seperator and the block      "
    " =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "
    "                                                              "
    " 3. Always put spaces between block identifiers and the block "
    "    itself                                                    "
    "                                                              "
    " 4. If a short comment requires multiple line, make sure that "
    "    the closing comment tag is the same multiple lines        "
    "                                                              "
    "                                                              "
    " =-=-=-=-=-=-=-=-=-=-=-=-=-= ---- =-=-=-=-=-=-=-=-=-=-=-=-=-= "

" =-=-=-=-=-=-=-=-= File Formatting Guideline -=-=-=-=-=-=-=-= "


" =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "


" =-=-=-=-=-=-=-=-=-=- Plugins Usin vim-plug =-=-=-=-=-=-=-=-= "

    " =- Call the vim-plug -= "
    call plug#begin('~/.config/nvim/plugged')

        " =-=-=-=-=-=-= Plug: ncm2 (Completion Framework) -=-=-=-=-=-= "

            " =- Call -= "
            Plug 'ncm2/ncm2'

            " =- Necessary for ncm2 -= "
            Plug 'roxma/nvim-yarp'

            " =- Enable ncm2 for all buffers (editors) -= "
            autocmd BufEnter * call ncm2#enable_for_buffer()

            " =- IMPORTANT: :help NCm2PopupOpen for more information -= "
            set completeopt=noinsert,menuone,noselect

            " =- NOTE: you need to install completion sources to get completions. Check -= "
            " =- our wiki page for a list of sources: https://github.com/ncm2/ncm2/wiki -= "
            Plug 'ncm2/ncm2-bufword'        " Words Completion Server
            Plug 'ncm2/ncm2-path'           " Path Completion Server
            Plug 'ncm2/ncm2-jedi'           " Python Completion Server
            Plug 'ncm2/ncm2-tern'           " JavaScript Completion Server

        " =-=-=-=-=-=-= Plug: ncm2 (Completion Framework) -=-=-=-=-=-= "


        " =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "


        " =-=-=-=-=-=-=-=- Theme and Syntax Highlighting =-=-=-=-=-=-= "

            " =- Color Theme | Onedark, closest to my other editors -= "
            Plug 'joshdick/onedark.vim'

            " =- Needed for onedark -= "
            Plug 'sheerun/vim-polyglot'

            " =- Lightline is the bottom bar -= "
            Plug 'itchyny/lightline.vim'

            " =- Set lightline color scheme to match main scheme -="
            let g:lightline = {
            \ 'colorscheme': 'onedark',
            \ }

        " =-=-=-=-=-=-=-=- Theme and Syntax Highlighting =-=-=-=-=-=-= "


        " =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "


        " =-=-=-=-=-=-=-=-=- Quality of Life Utilities =-=-=-=-=-=-=-= "

            " =- NERDTree File Menu -="
            Plug 'preservim/nerdtree' | 
            \ Plug 'Xuyuanp/nerdtree-git-plugin'

            " =- Git -="
            Plug 'https://github.com/airblade/vim-gitgutter.git'

            " =- NERDCommenter (Commenter keybinds) -="
            Plug 'preservim/nerdcommenter'

        " =-=-=-=-=-=-=-=-=- Quality of Life Utilities =-=-=-=-=-=-=-= "


        " =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "


        " =-=-=-=-=-= Plug: indentLine (Indentation Guide) =-=-=-=-=-= "

            " =- Call -= "
            Plug 'Yggdroot/indentLine'
            let g:indentLine_char = '│'
            let g:indentLine_leadingSpaceEnabled = 1
            let g:indentLine_leadingSpaceChar = '.'

        " =-=-=-=-=-= Plug: indentLine (Indentation Guide) =-=-=-=-=-= "


    " =- End vim-plug call -= "
    call plug#end()
  
" =-=-=-=-=-=-=-=-=-= Plugins Usin vim-plug -=-=-=-=-=-=-=-=-= "

  
" =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "

  
" =-=-=-=-=-=-=-= Additional NERDTree Settings =-=-=-=-=-=-=-= "

    " =- Start NERDTree and leave the curser in the other window -= "
    autocmd VimEnter * NERDTree | wincmd p

    " =- Keymaps for NERDTree -= "
    nnoremap <silent> <C-n><C-t> :NERDTreeToggle<CR>
    nnoremap <C-f> :NERDTreeFind

    " =- Exit Vim if NERDTree is the only window left -= "
    autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() |
        \ quit | endif

    " =- If another buffer tries to replace NERDTree, put it in the other window, and bring back NERDTree -= "
    autocmd BufEnter * if bufname('#') =~ 'NERD_tree_\d\+' && bufname('%') !~ 'NERD_tree_\d\+' && winnr('$') > 1 |
        \ let buf=bufnr() | buffer# | execute "normal! \<C-W>w" | execute 'buffer'.buf | endif

=-=-=-=-=-=-=-= Additional NERDTree Settings =-=-=-=-=-=-=-= "


" =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "

  
" =-=-=-=-=-=-= Additional NERDCommenter Settings =-=-=-=-=-=-= "

    " =- Makes sure it can comment an empty line -= "
    let g:NERDCommentEmptyLines = 1

    " =- Adds spaces after a line comment keepin it clean -= "
    let g:NERDSpaceDelims = 1

    " =- Shortcut so that <CTRL + /> will toggle comment -= "
    " =- Just like VSCode keybinds                       -= "
    noremap <C-_> :call NERDComment(0, "toggle")<CR>            " Any other mode
    inoremap <C-_> <ESC>:call NERDComment(0, "toggle")<CR>      " Insert mode

" =-=-=-=-=-=-= Additional NERDCommenter Settings =-=-=-=-=-=-= "


" =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "


" =-=-=-=-=-=-=-=-= Additional NCM2 Settings =-=-=-=-=-=-=-=-= "

    " =- Suppress the annoying 'match x ofy', 'the only match' -= "
    " =- and 'Pattern not found' messages                      -= "
    set shortmess+=c

    " =- CTRL-C doesn't trigger the InsertLeave autocmd . map to <ESC> instead -="
    inoremap <c-c> <ESC>

    " =- When the <Enter> key is pressed while the popup menu is visible, it only   -= "
    " =- hides the menu. Use this mapping to close the menu and also start a new    -= "
    " =- line.                                                                      -= "
    inoremap <expr> <CR> (pumvisible() ? "\<c-y>\<cr>" : "\<CR>")

    " =- Use <TAB> to select the popup menu: -= "
    inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
    inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

    " =- Wrap existing omnifunc                                                     -= "
    " =- Note that omnifunc does not run in background and may probably block the   -= "
    " =- editor. If you don't want to be blocked by omnifunc too often, you could   -= "
    " =- add 180ms delay before the omni wrapper:                                   -= "
    " =-  'on_complete': ['ncm2#on_complete#delay', 180,                            -= "
    " =-              \ 'ncm2#on_complete#omni', 'csscomplete#CompleteCSS'],        -= "
    au User Ncm2Plugin call ncm2#register_source({
        \ 'name' : 'css',
        \ 'priority': 9,
        \ 'subscope_enable': 1,
        \ 'scope': ['css','scss'],
        \ 'mark': 'css',
        \ 'word_pattern': '[\w\-]+',
        \ 'complete_pattern': ':\s*',
        \ 'on_complete': ['ncm2#on_complete#omni', 'csscomplete#CompleteCSS'],
        \ })

" =-=-=-=-=-=-=-=-= Additional NCM2 Settings =-=-=-=-=-=-=-=-= "


" =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "

  
" =-=-=-=-=-=-=-=-=-=-=-=-= Keybinds =-=-=-=-=-=-=-=-=-=-=-=-= "

    imap jk <Esc>
    imap kj <Esc>

    " =- Undo Redo -= "  
    noremap <C-z> :undo<CR>
    noremap <C-y> :redo<CR>

    " =- Write from buffer -= "
    noremap <C-w><C-r> :w<CR>

    " =- Save file will write from buffer -= "
    noremap <C-s> :w<CR>

" =-=-=-=-=-=-=-=-=-=-=-=-= Keybinds =-=-=-=-=-=-=-=-=-=-=-=-= "


" =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "


" =-=-=-=-=-=-=-=-=-=-=-=-=-= Misc =-=-=-=-=-=-=-=-=-=-=-=-=-= "

    " =- Tabs to spaces -= "
    set expandtab tabstop=4 shiftwidth=4 expandtab

    " =- Settings -= "
    set relativenumber

" =-=-=-=-=-=-=-=-=-=-=-=-=-= Misc =-=-=-=-=-=-=-=-=-=-=-=-=-= "


" =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "


" =-=-=-=-=-=-=-=-=-=-=-=-=-= Color -=-=-=-=-=-=-=-=-=-=-=-=-= "

    " =- Turn on Syntax highlighting -= "
    syntax on

    " =- Use onedark as color scheme -= "
    colorscheme onedark

" =-=-=-=-=-=-=-=-=-=-=-=-=-= Color -=-=-=-=-=-=-=-=-=-=-=-=-= "

" =-=-=-=-=-=-=-=-=-=-=-=-=-= |||| =-=-=-=-=-=-=-=-=-=-=-=-=-= "



" =-=-=-=-=-=-=-=-=-=-=-=-= FILE END =-=-=-=-=-=-=-=-=-=-=-=-= "
