#!/bin/sh

WEB=~/test.reednj.com
SRC=~/code/test.git
CONFIG=~/code/config_backup/test

# copy the required files to the website
rm -rf $WEB/*
cp -R $SRC/* $WEB
cp $CONFIG/* $WEB/config/

mkdir $WEB/tmp
touch $WEB/tmp/restart.txt

echo "Website deployed"
