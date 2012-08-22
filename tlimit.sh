#!/usr/bin/ksh
# tlimit.sh (c) 2012 <s@ctrlc.hu>

#  This is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.

# files exceeding their TTL are deleted from the disk
# useful for sharing files for a limited amount of downloads

# to alimit a file create a .<filename>.tlimit file containing the
# time of expiry as seconds since 1970/01/01 00:00:00

# alternative docroot can be specified as cmd param:
# ./tlimit.sh /home/user/public_html/putbox/

docroot=${1:-/var/www}

find "$docroot" -name '.*.tlimit' | while read limitfile; do
    [[ "$(head -1 $limitfile)" -ge "$(date +%s)" ]] && continue
    directory="${limitfile%/*}"
    tmp="${limitfile##*/}"
    tmp=${tmp##.}
    filename=${tmp%%.tlimit}
    rpath="$directory/$filename"
    alimit="$directory/.$filename.alimit"
    print "$(date --rfc-3339=ns) KILL $rpath"
    srm -fll "$rpath" "$limitfile" "$alimit";
done
