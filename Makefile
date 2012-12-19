INSTALLDIR=/soft/prog/BessyHDFViewer/

all: install

starpacks:
	# create starpacks with sdx
	sdx wrap BessyHDFViewer_Linux64 -vfs bessyhdfviewer.vfs/ -runtime Runtime/Linux_runtime64 
	sdx wrap BessyHDFViewer.exe -vfs bessyhdfviewer.vfs/ -runtime Runtime/Windows_runtime32.exe

install: starpacks
	cp -p BessyHDFViewer_Linux64 BessyHDFViewer.exe $(INSTALLDIR)
