":echo g:os

if g:os == "Darwin"
    let flags=' --quiet -f markdown+smart'
else
    let flags=' --smart -f markdown'
endif
":echo flags

:autocmd BufWritePost *.md
\   silent execute '!pandoc --standalone' . flags . ' --mathjax -t html "<afile>" >"'.
\   expand('<afile>:t:r').'".html'
