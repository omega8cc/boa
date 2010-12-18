#!/bin/bash


### Credits: Kevin @ http://www.mysqlperformanceblog.com/2009/04/15/how-to-decrease-innodb-shutdown-times

DATABASEUSER=root
DATABASEPASS=NdKBu34erty325r6mUHxWy
pct=0


# Call the given function, require that it complete successfully, and then return the status.
#
rcall() {

    echo -n '+'
    echo -n $@

    $@

    status=$?

    if [ $status != 0 ]; then
        echo " FAILED"
        exit $status
    fi

    echo

    return $status

}


if [ "$1" = "--allow_dirty_buffers" ]; then
    pct=90
fi


innodb_status=$(echo "SHOW ENGINES;" | rcall mysql --user=$DATABASEUSER --pass=$DATABASEPASS | grep InnoDB | cut -f2)

if [ "$innodb_status" = "DISABLED" ]; then
    echo "The Innodb storage engine is disabled"
    exit 0
fi


# tell mysql that we need to shutdown so start flushing dirty pages to disk.
# Normally InnoDB does this by itself but only when port 3306 is closed which
# prevents us from monitoring the box.

rcall mysql --user=$DATABASEUSER --pass=$DATABASEPASS <<EOF

SLAVE STOP;
SET GLOBAL innodb_max_dirty_pages_pct=$pct;

EOF

# ..... now wait until the dirty buffer size goes down to zero.

IFS=
if [ "$1" = "--progress" ]; then

echo "Innodb dirty pages:"

    while [ true ]; do
        
        status=$(echo 'SHOW INNODB STATUS\G' | rcall mysql --user=$DATABASEUSER --pass=$DATABASEPASS)

        modified_db_pages=$(echo $status | grep -E '^Modified db pages' | grep -Eo '[0-9]+$')

        if [ "$modified_db_pages" = "0" ]; then
            echo
            break
        fi

        echo -ne "$modified_db_pages\r";
        sleep 1
    done

fi

