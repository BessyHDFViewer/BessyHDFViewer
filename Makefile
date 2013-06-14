INSTALLDIR=/soft/prog/BessyHDFViewer/

all: install

starpacks:
	# create starpacks with sdx
	sdx wrap BessyHDFViewer_Linux32 -vfs bessyhdfviewer.vfs/ -runtime Runtime/Linux_runtime32
	sdx wrap BessyHDFViewer_Linux64 -vfs bessyhdfviewer.vfs/ -runtime Runtime/Linux_runtime64 
	sdx wrap BessyHDFViewer.exe -vfs bessyhdfviewer.vfs/ -runtime Runtime/Windows_runtime32.exe

install: starpacks
	cp -p BessyHDFViewer_Linux64 BessyHDFViewer_Linux32 BessyHDFViewer.exe $(INSTALLDIR)
	# install to BAM
	scp  BessyHDFViewer_Linux64 ptb@bam15.usr.bessy.de:/soft/home/ptb/BessyHDFViewer/BessyHDFViewer_Linux64

mac:
	# create application for Mac OSX
	sdx wrap BessyHDFViewer.app/Contents/MacOS/BessyHDFViewer -vfs bessyhdfviewer.vfs/ -runtime Runtime/Mac_runtime64
	# make icons
	cd ArtWork && make mac
	cp ArtWork/BessyHDFViewer.icns BessyHDFViewer.app/Contents/Resources/
