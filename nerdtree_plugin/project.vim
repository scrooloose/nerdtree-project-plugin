" Features of projects:
"
" * Tree state (open/closed dirs) is remembered between sessions
" * Dirs can be hidden.
"
" Usage:
"
"     Creating/Loading/Deleting projects:
"
"         Create a project from the current nerdtree with
"           :NERDTreeProjectSave <name>
"
"         Load a project with
"           :NERDTreeProjectLoad <name>
"
"         Load a project from the current CWD
"           :NERDTreeProjectLoadFromCWD
"
"         Delete a project with
"           :NERDTreeProjectRm <name>
"
"
"         Note: <name> above will tab complete.
"
"     Hiding/Unhiding directories in projects
"         To hide a dir, put the cursor on it and hit 'mph'. 'mp' opens the
"         menu and goes to the projects submenu, then 'h' hides it.
"
"         To unhide, turn off file filters (default: f), then put the cursor
"         on the dir in question and hit 'mpu'
"
"
"============================================================

if exists("g:loaded_nerdtree_project_plugin")
    finish
endif
let g:loaded_nerdtree_project_plugin=1

"Glue code - wiring up s:Project into nerdtree {{{1
"============================================================
command! -nargs=1 NERDTreeProjectSave call g:NERDTreeProject.Add(<q-args>, b:NERDTree)
command! -nargs=1 -complete=customlist,NERDTreeCompleteProjectNames NERDTreeProjectLoad call g:NERDTreeProject.Open(<q-args>)
command! -nargs=1 -complete=customlist,NERDTreeCompleteProjectNames NERDTreeProjectRm call g:NERDTreeProject.Remove(<q-args>)
command! -nargs=0 -complete=customlist,NERDTreeCompleteProjectNames NERDTreeProjectLoadFromCWD call g:NERDTreeProject.LoadFromCWD()

function! NERDTreeCompleteProjectNames(A,L,P) abort
    if empty(s:Project.All())
        return 0
    endif
    let names = map(copy(s:Project.All()), 'v:val.getName()')
    return filter(names, 'v:val =~# "^' . a:A . '"')
endfunction

augroup nerdtreeproject
    autocmd bufunload,bufwipeout * call g:NERDTreeProject.UpdateProjectInBuf(bufnr(bufname(expand("<afile>"))))
augroup end

"CLASS: Project {{{1
"============================================================
let s:Project = {}
let g:NERDTreeProject = s:Project

"Class Methods {{{2
"============================================================
" FUNCTION: Project.Add(name, nerdtree) {{{3
function! s:Project.Add(name, nerdtree) abort
    for i in s:Project.All()
        if i.getName() ==# a:name
            return i.update(a:nerdtree)
        endif
    endfor

    let newProj = s:Project.New(a:name, a:nerdtree)
    call add(s:Project.All(), newProj)
    call s:Project.Write()
    call newProj.open()
endfunction

" FUNCTION: Project.All() {{{3
function! s:Project.All() abort
    if !exists("s:Project._All")
        let s:Project._All = []
        call s:Project.Read()
    endif
    return s:Project._All
endfunction

" FUNCTION: Project.Remove() {{{3
function! s:Project.Remove(name) abort
    for i in s:Project.All()
        if i.getName() ==# a:name
            let idx = index(s:Project.All(), i)
            call remove(s:Project.All(), idx)
            call s:Project.Write()
            return nerdtree#echo("Project removed.")
        endif
    endfor
    call nerdtree#echo("No project found with name: '" . a:name . "'")
endfunction

" FUNCTION: Project.New(name, nerdtree) {{{3
function! s:Project.New(name, nerdtree, ...) abort
    if a:name =~# ' '
        throw "NERDTree.IllegalProjectNameError: illegal name:" . a:name
    endif

    let newObj = copy(self)
    let newObj._name = a:name
    let newObj._rootPath = a:nerdtree.root.path

    let opts = a:0 ? a:1 : {}
    if has_key(opts, 'openDirs')
        let newObj._openDirs = opts['openDirs']
    else
        let newObj._openDirs = newObj._extractOpenDirs(a:nerdtree.root)
    endif

    let newObj._hiddenDirs = has_key(opts, 'hiddenDirs') ? opts['hiddenDirs'] : []

    call newObj.rebuildHiddenRegex()

    return newObj
endfunction

" FUNCTION: Project.FindByName(name) {{{3
function! s:Project.FindByName(name) abort
    for i in s:Project.All()
        if i.getName() ==# a:name
            return i
        endif
    endfor
    throw "NERDTree.NoProjectError: no project found for name: \"". a:name  .'"'
endfunction

" FUNCTION: Project.FindByRoot(dir) {{{3
function! s:Project.FindByRoot(dir) abort
    for i in s:Project.All()
        if i.getRootPath().equals(a:dir)
            return i
        endif
    endfor
    throw "NERDTree.NoProjectError: no project found for root: \"". a:dir.str()  .'"'
endfunction

" FUNCTION: Project.LoadFromCWD() {{{3
function! s:Project.LoadFromCWD() abort
    try
        let proj = s:Project.FindByRoot(g:NERDTreePath.New(getcwd()))
        call proj.open()
        wincmd w
    catch /NERDTree.NoProjectError/
        call nerdtree#echo("Couldn't find a project for root: " . getcwd())
        NERDTree
    endtry
endfunction

" FUNCTION: Project.Open(name) {{{3
function! s:Project.Open(name) abort
    call s:Project.FindByName(a:name).open()
endfunction

" FUNCTION: Project.OpenForRoot(dir) {{{3
function! s:Project.OpenForRoot(dir) abort
    let p = s:Project.FindByRoot(a:dir)
    if !empty(p)
        call p.open()
    endif
endfunction

" FUNCTION: Project.ProjectFileName() {{{3
function! s:Project.ProjectFileName() abort
    return expand("~/.NERDTreeProjects")
endfunction

" FUNCTION: Project.Read() {{{3
function! s:Project.Read() abort
    if !filereadable(s:Project.ProjectFileName())
        return []
    endif

    try
        exec "let projHashes = " . readfile(s:Project.ProjectFileName())[0]
    catch
        return []
    endtry

    for projHash in projHashes
        let nerdtree = g:NERDTree.New(g:NERDTreePath.New(projHash['rootPath']), "tab")
        let project = s:Project.New(projHash['name'], nerdtree, { 'openDirs': projHash['openDirs'], 'hiddenDirs': projHash['hiddenDirs'] })
        call add(s:Project.All(), project)
    endfor
endfunction

" FUNCTION: Project.UpdateProjectInBuf(bufnr) {{{3
function! s:Project.UpdateProjectInBuf(bufnr) abort
    let nerdtree = getbufvar(a:bufnr, "NERDTree")

    if empty(nerdtree)
        return
    endif

    if !has_key(nerdtree, '__currentProject')
        return
    endif

    let proj = nerdtree.__currentProject

    call proj.update(nerdtree)
endfunction

" FUNCTION: Project.Write() {{{3
function! s:Project.Write() abort
    let projHashes = []

    for proj in s:Project.All()
        let hash = {
            \ 'name': proj.getName(),
            \ 'openDirs': proj.getOpenDirs(),
            \ 'rootPath': proj.getRootPath().str(),
            \ 'hiddenDirs': proj.getHiddenDirs()
        \ }

        call add(projHashes, hash)
    endfor

    call writefile([string(projHashes)], s:Project.ProjectFileName())
endfunction

"Instance Methods {{{2
"============================================================
" FUNCTION: Project.extractOpenDirs(rootNode) {{{3
function! s:Project._extractOpenDirs(rootNode) abort
    let retVal = []

    for node in a:rootNode.getDirChildren()
        if node.isOpen
            call add(retVal, node.path.str())

            let childOpenDirs = self._extractOpenDirs(node)
            if !empty(childOpenDirs)
                let retVal = retVal + childOpenDirs
            endif
        endif
    endfor

    return retVal
endfunction

" FUNCTION: Project.getHiddenDirs() {{{3
function! s:Project.getHiddenDirs() abort
    return self._hiddenDirs
endfunction

" FUNCTION: Project.getName() {{{3
function! s:Project.getName() abort
    return self._name
endfunction

" FUNCTION: Project.getOpenDirs() {{{3
function! s:Project.getOpenDirs() abort
    return self._openDirs
endfunction

" FUNCTION: Project.getRoot() {{{3
function! s:Project.getRootPath() abort
    return self._rootPath
endfunction

" FUNCTION: Project.hideDir(path) {{{3
function! s:Project.hideDir(path) abort
    if self.isHidden(a:path)
        return
    endif

    call add(self._hiddenDirs, a:path)
    call self.rebuildHiddenRegex()
endfunction

" FUNCTION: Project.isHidden(path) {{{3
function! s:Project.isHidden(path) abort
    for dir in self._hiddenDirs
        if dir == a:path
            return 1
        endif
    endfor
endfunction

" FUNCTION: Project.open() {{{3
function! s:Project.open() abort
    call g:NERDTreeCreator.CreateTabTree(self.getRootPath().str())

    for dir in self.getOpenDirs()
        let p = g:NERDTreePath.New(dir)
        call b:NERDTree.root.reveal(p, { "open": 1 })
    endfor

    let b:NERDTree.__currentProject = self
    call b:NERDTree.render()
endfunction

" FUNCTION: Project.rebuildHiddenRegex() {{{3
function! s:Project.rebuildHiddenRegex() abort
    let hiddenDirs = join(map(copy(self._hiddenDirs), "v:val . '\\.\\*'"), '\|')
    let self._hiddenRegex = '\M\(' . hiddenDirs . '\)'
endfunction

" FUNCTION: Project.unhideDir(path) {{{3
function! s:Project.unhideDir(path) abort
    if !self.isHidden(a:path)
        return
    endif

    let idx = index(self._hiddenDirs, a:path)
    if idx != -1
        call remove(self._hiddenDirs, idx)
    endif

    call self.rebuildHiddenRegex()
endfunction

" FUNCTION: Project.update(nerdtree) {{{3
function s:Project.update(nerdtree)
    "make sure the user hasn't browsed away from the project dir
    if !a:nerdtree.root.path.equals(self.getRootPath())
        return
    endif

    let self._openDirs = self._extractOpenDirs(a:nerdtree.root)
    call s:Project.Write()
endfunction

"Filtering glue {{{1
"============================================================

call NERDTreeAddPathFilter("ProjectPathFilter")

function! ProjectPathFilter(params) abort
    let nerdtree = a:params['nerdtree']

    "bail if we haven't loaded a project
    if !exists('nerdtree.__currentProject')
        return
    endif

    if len(nerdtree.__currentProject._hiddenDirs) == 0
        return 0
    endif

    let p = a:params['path']

    return p.str() =~ nerdtree.__currentProject._hiddenRegex
endfunction

let projectMenu = NERDTreeAddSubmenu({'text': '(p)rojects', 'shortcut': 'p'})
call NERDTreeAddMenuItem({
            \ 'text': '(h)ide directory',
            \ 'shortcut': 'h',
            \ 'parent': projectMenu,
            \ 'callback': 'NERDTreeProjectHideMenuItemCallback'
            \ })

function! NERDTreeProjectHideMenuItemCallback() abort
    let node = g:NERDTreeDirNode.GetSelected()
    if empty(node)
        return
    endif

    call b:NERDTree.__currentProject.hideDir(node.path.str())
    call b:NERDTree.render()
endfunction

call NERDTreeAddMenuItem({
            \ 'text': '(u)nhide directory',
            \ 'shortcut': 'u',
            \ 'parent': projectMenu,
            \ 'callback': 'NERDTreeProjectUnhideMenuItemCallback'
            \ })

function! NERDTreeProjectUnhideMenuItemCallback() abort
    let node = g:NERDTreeDirNode.GetSelected()
    if empty(node)
        return
    endif

    call b:NERDTree.__currentProject.unhideDir(node.path.str())
    call b:NERDTree.render()
endfunction

" vi: fdm=marker
