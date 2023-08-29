build/wp2.pdf: wp2.tex macro.tex 
	mkdir -p build
	pdflatex -synctex=1 -interaction=batchmode -output-directory=build wp2

build-once:
	pdflatex -synctex=1 -interaction=batchmode -output-directory=build wp2

debug:
	pdflatex -synctex=1 -output-directory=build wp2

