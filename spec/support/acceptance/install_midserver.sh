#!/bin/bash

useradd midserver

host=https://install.service-now.com
path=glide/distribution/builds/package/app-signed/mid-linux-installer/2021/01/15
file=mid-linux-installer.quebec-12-09-2020__patch0-hotfix2-01-08-2021_01-15-2021_1853.linux.x86-64.deb
devinstance=$1
ca_cert_path=$(puppet config print cacert)

curl "$host/$path/$file" -O

dpkg -i $file

/opt/servicenow/mid/agent/installer.sh \
      -silent \
      -INSTANCE_URL $devinstance \
      -USE_PROXY N \
      -MID_USERNAME MIDServer \
      -MID_PASSWORD password1 \
      -MID_NAME linux_midserver \
      -APP_NAME midserver \
      -APP_LONG_NAME midserver \
      -NON_ROOT_USER midserver

/opt/servicenow/mid/agent/jre/bin/keytool \
        -import \
        -alias puppet \
        -file $ca_cert_path \
        -keystore /opt/servicenow/mid/agent/jre/lib/security/cacerts \
        -storepass changeit \
        -noprompt