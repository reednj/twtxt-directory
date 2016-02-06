#!/bin/sh

WEB=~/www/twtxt.reednj.com
SRC=~/code/twtxt.git
CONFIG=~/code/config_backup/twtxt

# update the version file
git --git-dir=$SRC describe --long --always --abbrev=3 > version.txt

# update the data
mkdir $SRC/data
cp $WEB/data/* $SRC/data

# copy the required files to the website
rm -rf $WEB/*
cp -R $SRC/* $WEB
cp $CONFIG/* $WEB/config/

mkdir $WEB/tmp
touch $WEB/tmp/restart.txt

echo "Website deployed"

