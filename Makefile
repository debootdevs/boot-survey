build/wp2.pdf: wp2.tex document.tex macro.tex  build/wp2.bbl
	mkdir -p build
	pdflatex -synctex=1 -interaction=batchmode -output-directory=build wp2

build-once:
	pdflatex -synctex=1 -interaction=batchmode -output-directory=build wp2

debug:
	pdflatex -synctex=1 -output-directory=build wp2


build/wp2.bbl: build/wp2.bcf
	biber build/wp2 --quiet

build/wp2.bcf: wp2.tex  
	pdflatex -synctex=1 -interaction=batchmode -output-directory=build wp2

