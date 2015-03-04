SRCS=$(wildcard *.md)

HTMLS=$(SRCS:.md=.html)

%.html: %.md
	@echo "Compiling $< -> $*.html"
	markdown $< >$*.html

all: $(HTMLS)
	@echo "HTMLs: $(HTMLS)"
	@echo "MDs: $(SRCS)"
