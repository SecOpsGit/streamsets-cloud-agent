#!/bin/bash

dirs=$(ls -l /stage-lib-volume/*/stagelib.txt | wc -l)
echo "StageLibraries Downloaded till now $dirs / $1"

while [ $dirs -lt $1 ]
do
  dirs=$(ls -l /stage-lib-volume/*/stagelib.txt | wc -l)
  echo "StageLibraries Downloaded till now $dirs / $1"
done

echo "Stage Libraries Downloaded $dirs"

cp -rf /opt/streamsets-libs/* /stage-lib-volume/

"${SDC_HOME}/bin/streamsets" dc
