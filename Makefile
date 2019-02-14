# 
# File : Makefile
# Author: Amine Amanzou
#
## Created on 4 janvier 2013
#
#
#

CC = gcc

OFILES = client.o \
	server.o 

CFILECLT = client.c

CFILESRV = server.c

EXESRV = server

EXECLT = client

all : MKD ${EXESRV} ${EXECLT}

MKD : 
	mkdir out

${EXESRV} :
	$(CC) $(CFLAGS) -o out/${EXESRV} ${CFILESRV}

${EXECLT} :
	$(CC) $(CFLAGS) -o out/${EXECLT} ${CFILECLT}

# nettoyage des fichiers crees
clean :
	rm -rf ${OFILES} out *~
                 
mrproper : clean but

.PHONY : but clean mrproper

# fin du Makefile



