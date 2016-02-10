#!/bin/sh

WEB=~/www/twtxt.reednj.com
SRC=~/code/twtxt.git
CONFIG=~/code/config_backup/twtxt

# update the data
mkdir $SRC/data
cp $WEB/data/* $SRC/data

# update the data
cp $WEB/public/twtxt/*.txt $SRC/public/twtxt

# copy the required files to the website
rm -rf $WEB/*
cp -R $SRC/* $WEB
cp $CONFIG/* $WEB/config/

mkdir $WEB/tmp
touch $WEB/tmp/restart.txt

echo "Website deployed"

