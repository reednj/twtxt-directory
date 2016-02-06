#!/bin/sh

WEB=~/twtxt.reednj.com
SRC=~/code/twtxt.git
CONFIG=~/code/config_backup/twtxt

# copy the required files to the website
rm -rf $WEB/*
cp -R $SRC/* $WEB
cp $CONFIG/* $WEB/config/

mkdir $WEB/tmp
touch $WEB/tmp/restart.txt

echo "Website deployed"

