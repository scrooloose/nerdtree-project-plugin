" Usage:
"
"   Create a project from the current nerdtree with
"     :NERDTreeProjectSave <name>
"
"   Load a project with
"     :NERDTreeProjectLoad <name>
"
"   Delete a project with
"     :NERDTreeProjectRm <name>
"
"   Note: <name> above will tab complete.
"
"
" Tree state (open/closed dirs) will be remembered when you return to a
" project.
"
"============================================================

if exists("g:loaded_nerdtree_project_plugin")
    finish
endif
let g:loaded_nerdtree_project_plugin=1


"Glue code - wiring up s:Project into nerdtree
"============================================================
command! -nargs=1 NERDTreeProjectSave call g:NERDTreeProject.Add(<q-args>, b:NERDTree)
command! -nargs=1 -complete=customlist,NERDTreeCompleteProjectNames NERDTreeProjectLoad call g:NERDTreeProject.Open(<q-args>)
command! -nargs=1 -complete=customlist,NERDTreeCompleteProjectNames NERDTreeProjectRm call g:NERDTreeProject.Remove(<q-args>)

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

"CLASS: Project
"============================================================
let s:Project = {}
let g:NERDTreeProject = s:Project

"Class Methods
"============================================================
" FUNCTION: Project.Add(name, nerdtree) {{{1
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

" FUNCTION: Project.All() {{{1
function! s:Project.All() abort
    if !exists("s:Project._All")
        let s:Project._All = []
        call s:Project.Read()
    endif
    return s:Project._All
endfunction

" FUNCTION: Project.Remove() {{{1
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

" FUNCTION: Project.New(name, nerdtree) {{{1
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

    return newObj
endfunction

" FUNCTION: Project.FindByName(name) {{{1
function! s:Project.FindByName(name) abort
    for i in s:Project.All()
        if i.getName() ==# a:name
            return i
        endif
    endfor
    throw "NERDTree.NoProjectError: no project found for name: \"". a:name  .'"'
endfunction

" FUNCTION: Project.Open(name) {{{1
function! s:Project.Open(name) abort
    call s:Project.FindByName(a:name).open()
endfunction

" FUNCTION: Project.ProjectFileName() {{{1
function! s:Project.ProjectFileName() abort
    return expand("~/.NERDTreeProjects")
endfunction

" FUNCTION: Project.Read() {{{1
function! s:Project.Read() abort
    if !filereadable(s:Project.ProjectFileName())
        return []
    endif

    exec "let projHashes = " . readfile(s:Project.ProjectFileName())[0]

    for projHash in projHashes
        let nerdtree = g:NERDTree.New(g:NERDTreePath.New(projHash['rootPath']), "tab")
        let project = s:Project.New(projHash['name'], nerdtree, { 'openDirs': projHash['openDirs']})
        call add(s:Project.All(), project)
    endfor
endfunction

" FUNCTION: Project.UpdateProjectInBuf(bufnr) {{{1
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

" FUNCTION: Project.Write() {{{1
function! s:Project.Write() abort
    let projHashes = []

    for proj in s:Project.All()
        let hash = {
            \ 'name': proj.getName(),
            \ 'openDirs': proj.getOpenDirs(),
            \ 'rootPath': proj.getRootPath().str()
        \ }

        call add(projHashes, hash)
    endfor

    call writefile([string(projHashes)], s:Project.ProjectFileName())
endfunction

"Instance Methods
"============================================================

" FUNCTION: Project.extractOpenDirs(rootNode) {{{1
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

" FUNCTION: Project.getName() {{{1
function! s:Project.getName() abort
    return self._name
endfunction

" FUNCTION: Project.getOpenDirs() {{{1
function! s:Project.getOpenDirs() abort
    return self._openDirs
endfunction

" FUNCTION: Project.getRoot() {{{1
function! s:Project.getRootPath() abort
    return self._rootPath
endfunction

" FUNCTION: Project.open() {{{1
function! s:Project.open() abort
    if g:NERDTree.IsOpen()
        call g:NERDTree.CursorToTreeWin()
    else
        call g:NERDTreeCreator.ToggleTabTree('')
    endif

    let newRoot = g:NERDTreeFileNode.New(self.getRootPath(), b:NERDTree)
    call b:NERDTree.changeRoot(newRoot)

    for dir in self.getOpenDirs()
        let p = g:NERDTreePath.New(dir)
        call b:NERDTree.root.reveal(p, { "open": 1 })
    endfor

    call b:NERDTree.render()
    let b:NERDTree.__currentProject = self
endfunction

" FUNCTION: Project.update(nerdtree) {{{1
function s:Project.update(nerdtree)
    "make sure the user hasn't browsed away from the project dir
    if !a:nerdtree.root.path.equals(self.getRootPath())
        return
    endif

    let self._openDirs = self._extractOpenDirs(a:nerdtree.root)
    call s:Project.Write()
endfunction

" vi: fdm=marker
