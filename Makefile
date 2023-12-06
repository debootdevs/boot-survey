build/wp2.pdf: wp2.tex document.tex macro.tex  build/wp2.bbl build
	pdflatex -synctex=1 -interaction=batchmode -output-directory=build wp2

build-once:
	pdflatex -synctex=1 -interaction=batchmode -output-directory=build wp2

debug:
	pdflatex -synctex=1 -output-directory=build wp2

build:
	mkdir -p build

build/wp2.bbl: build/wp2.bcf build
	biber build/wp2 --quiet

build/wp2.bcf: wp2.tex build
	pdflatex -synctex=1 -interaction=batchmode -output-directory=build wp2

wp2.bib: wp2.tex build/wp2.bcf
	biber wp2 --input-directory=build --output-format=bibtex
	mv wp2_biber.bib $@
	rm *.blg

.PHONY: clean debug build-once

clean:
	rm build/*