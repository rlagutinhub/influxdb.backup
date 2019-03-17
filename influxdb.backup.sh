#!/bin/bash
# ----------------------------------------------------------------------------------------------------
# NAME:    INFLUXDB.BACKUP.SH
# DESC:    SCRIPT FOR BACKUP INFLUXDB
# DATE:    16.03.2019
# LANG:    BASH
# AUTOR:   LAGUTIN R.A.
# CONTACT: RLAGUTIN@MTA4.RU
# ----------------------------------------------------------------------------------------------------

# https://docs.influxdata.com/influxdb/v1.7/administration/backup_and_restore/
# https://www.influxdata.com/blog/new-features-in-open-source-backup-and-restore/

SCR_NAME=$(basename $0)
SCR_DATE_BEFORE=$(date +%s)

INFLUX_BACKUP_DIR=/backup
INFLUX_BACKUP_DISK=$INFLUX_BACKUP_DIR
INFLUX_BACKUP_DISK_THRESHOLD=10 # free space, percent %
INFLUX_BACKUP_LOG=$INFLUX_BACKUP_DIR/$SCR_NAME.$(date +%Y.%m.%d_%H.%M.%S_%N).log

# MAILSERVER="mail.example.com"
MAILSERVER="localhost"
MAILPORT=25
MAILFROM="$SCR_NAME <$HOSTNAME@example.com>"
MAILTO="lagutin_ra@example.com"
MAIL_VERBOSE="ONLY_FAIL" # ONLY_FAIL or FAIL_OK or OK

# $1 = $INFLUX_BACKUP_DISK
# $2 = $INFLUX_BACKUP_DISK_THRESHOLD
function f_check_free_disk_space() {

    local check_free_disk_space=$(df -k $1 | tail -n1 | awk -F " " '{print($5)}' | awk -F "%" '{print($1)}' | awk '{print($1)}')
    if [ $(( 100 - check_free_disk_space )) -ge $2 ]; then return 0; else return 1; fi

}

function f_elapsed_time() {

    SCR_DATE_AFTER="$(date +%s)"
    ELAPSED="$(expr $SCR_DATE_AFTER - $SCR_DATE_BEFORE)"
    HOURS=$(($ELAPSED / 3600))
    ELAPSED=$(($ELAPSED - $HOURS * 3600))
    MINUTES=$(($ELAPSED / 60))
    SECONDS=$(($ELAPSED - $MINUTES * 60))
    ELAPSED_TIME="elapsed ${HOURS}h:${MINUTES}m:${SECONDS}s"

}

function f_backup_influxdb() {

    # $1 = $INFLUX_DB_NAME
    # $2 = $INFLUX_HOST
    # $3 = $INFLUX_PORT
    if [ $# -eq 3 ]; then
        INFLUX_BACKUP_DATE_CUR=$(date +%Y-%m-%dT%H:%M:%SZ)
        INFLUX_BACKUP_DATE_CUR_MOD="${INFLUX_BACKUP_DATE_CUR//:/.}"
        if [ ! -d "$INFLUX_BACKUP_DIR/full.$1.$INFLUX_BACKUP_DATE_CUR_MOD" ]; then mkdir -p "$INFLUX_BACKUP_DIR/full.$1.$INFLUX_BACKUP_DATE_CUR_MOD"; fi
        echo -en "\\033[0;1m"; echo -en "exec: "; echo -en "\\033[0;36m"; echo -en $(which influxd) backup -database "$1" -portable -host "$2:$3" "$INFLUX_BACKUP_DIR/full.$1.$INFLUX_BACKUP_DATE_CUR_MOD"; echo -en "\\033[0;39m"; echo -e
        $(which influxd) backup -database "$1" -portable -host "$2:$3" "$INFLUX_BACKUP_DIR/full.$1.$INFLUX_BACKUP_DATE_CUR_MOD"
    # $1 = $INFLUX_DB_NAME
    # $2 = $INFLUX_HOST
    # $3 = $INFLUX_PORT
    # $4 = $INFLUX_TIME_BACK
    elif [ $# -eq 4 ];then
        INFLUX_BACKUP_DATE_CUR=$(date +%Y-%m-%dT%H:%M:%SZ)
        INFLUX_BACKUP_DATE_CUR_MOD="${INFLUX_BACKUP_DATE_CUR//:/.}"
        INFLUX_BACKUP_DATE_OLD=$(date +%Y-%m-%dT%H:%M:%SZ --date="-$4 minute")
        INFLUX_BACKUP_DATE_OLD_MOD="${INFLUX_BACKUP_DATE_OLD//:/.}"
        if [ ! -d "$INFLUX_BACKUP_DIR/range.$1.$INFLUX_BACKUP_DATE_CUR_MOD-$INFLUX_BACKUP_DATE_OLD_MOD" ]; then mkdir -p "$INFLUX_BACKUP_DIR/range.$1.$INFLUX_BACKUP_DATE_CUR_MOD-$INFLUX_BACKUP_DATE_OLD_MOD"; fi
        echo -en "\\033[0;1m"; echo -en "exec: "; echo -en "\\033[0;36m"; echo -en $(which influxd) backup -database "$1" -portable -host "$2:$3" -start "$INFLUX_BACKUP_DATE_OLD" "$INFLUX_BACKUP_DIR/range.$1.$INFLUX_BACKUP_DATE_CUR_MOD-$INFLUX_BACKUP_DATE_OLD_MOD"; echo -en "\\033[0;39m"; echo -e
        $(which influxd) backup -database "$1" -portable -host "$2:$3" -start "$INFLUX_BACKUP_DATE_OLD" "$INFLUX_BACKUP_DIR/range.$1.$INFLUX_BACKUP_DATE_CUR_MOD-$INFLUX_BACKUP_DATE_OLD_MOD"
    fi

    if [ $? -eq 0 ]; then return 0; else return 1; fi

}

# $1 = $INFLUX_BACKUP_DIR
# $2 = $INFLUX_DB_NAME
# $3 = $INFLUX_ROT
function f_rotate() {

    for path in `find "$1" -type d -regextype sed -regex ".*$2.*[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}\.[0-9]\{2\}\.[0-9]\{2\}Z$" -prune -mmin +$3`; do
        echo -en "\\033[0;1m"; echo -en "delete: "; echo -en "\\033[0;33m"; echo -en "$path"; echo -en "\\033[0;32m"; echo -en " # older $3 minutes"; echo -en "\\033[0;39m"; echo -e
        rm -rf $path
    done

}

# $1 = FAIL or OK
# $2 = $INFLUX_BACKUP_RES
function f_mailer(){

    echo "helo $(hostname -f)"; sleep 2
    echo "MAIL FROM: <$MAILFROM>"; sleep 2
    echo "RCPT TO: <$MAILTO>"; sleep 2
    echo "DATA"; sleep 2
    echo "From: <$MAILFROM>"
    echo "To: <$MAILTO>"
    echo "Subject: $1 - $SCR_NAME"
    echo "$2"
    echo
    echo "For more information look at log:"
    echo "$INFLUX_BACKUP_LOG"
    sleep 4
    echo "."
    sleep 4
    echo "quit"

}

# $1 = FAIL or OK
# $2 = $INFLUX_BACKUP_RES
function f_logger() {
 
    if [ "$1" == "FAIL" ]; then
        echo "$2" | $(which systemd-cat) -t $SCR_NAME -p err
    elif [ "$1" == "OK" ]; then
        echo "$2" | $(which systemd-cat) -t $SCR_NAME -p info
    fi
 
}

f_usage() {

    echo "Available options for influxdb backup script:"
    echo
    echo -e " -dbs | --databases   Sets list of databases to back up with the following parameters:"
    echo
    echo -e "     -n | --name      - database name for backup"
    echo -e "     -t | --timeback  - number of minutes ago, where the backup will include all data"
    echo -e "                        from the current time minus the specified number of minutes to the current time."
    echo -e "                        if not set, then full backup!"
    echo -e "     -r | --rotate    - Sets number of minutes to keep backup before rotate."
    echo
    echo -e " -h | --host            Sets influxdb host."
    echo -e " -p | --port            Sets influxdb port."
    echo
    echo -e " --help                 Shows this help output."
    echo -e " --recovery             Shows plan of disaster recovery."
    echo
    echo "Note: Do not backup for db _internal, because it cannot be recovered from this backup."
    echo -e "\n Example: ./influxdb.backup.sh -dbs -n \"telegraf\" -t 43200 -r 43200 -n \"chronograf\" -r 43200 -h \"localhost\" -p 8088"
    echo

}

f_recovery() {

    cat <<EOF
# Disaster recovery
# https://docs.influxdata.com/influxdb/v1.7/administration/backup_and_restore/
# https://www.influxdata.com/blog/new-features-in-open-source-backup-and-restore/

Important: If after restored status of clients is offline and they not sending new data, that is failed restore influxdb data!!!

# before required
systemctl stop kapacitor.service
systemctl stop chronograf.service
systemctl stop grafana-server.service
systemctl stop nginx.service

# clear influxdb config
systemctl stop influxdb.service
rm -rf /var/lib/influxdb/*
systemctl start influxdb.service

# create admin user
influx
CREATE USER "admin" WITH PASSWORD 'your-password' WITH ALL PRIVILEGES
exit

# check admin user
influx -username 'admin' --password '' -host 'localhost'
SHOW USERS
exit

# restore db telegraf (include retention policys and all shards)
influxd restore -portable -db telegraf -host localhost:8088 path-to-backup

# restore db chronograf (include retention policys and all shards)
influxd restore -portable -db chronograf -host localhost:8088 path-to-backup

# check restored db
influx -username 'admin' --password '' -host 'localhost'
SHOW DATABASES
exit

# manual restore security
influx -username 'admin' --password '' -host 'localhost'
CREATE USER "telegraf" WITH PASSWORD 'your-password'
CREATE USER "kapacitor" WITH PASSWORD 'your-password' WITH ALL PRIVILEGES
CREATE USER "chronograf" WITH PASSWORD 'your-password'
CREATE USER "grafana" WITH PASSWORD 'your-password'
GRANT WRITE ON "telegraf" TO "telegraf"
GRANT READ ON "telegraf" TO "chronograf"
GRANT ALL ON "chronograf" TO "chronograf"
GRANT READ ON "telegraf" TO "grafana"
SHOW GRANTS FOR telegraf
SHOW GRANTS FOR kapacitor
SHOW GRANTS FOR chronograf
SHOW GRANTS FOR grafana
SHOW USERS
exit

# after required
systemctl restart influxdb.service
systemctl start kapacitor.service
systemctl start chronograf.service
systemctl start grafana-server.service
systemctl start nginx.service

# troubleshooting client (after restore)

1. in chronograf status for this client - offline
journalctl --full -u telegraf.service
[outputs.influxdb] when writing to [http://influxdb.example.com:8086]: 403 Forbidden: "telegraf" user is not authorized to write to database "telegraf"
[agent] Error writing to output [influxdb]: could not write any address

systemctl restart telegraf.service # resolve

2. check connection telegraf to influxdb
curl -k -i http://influxdb.example.com:8086/ping # ok if return 204

3. check correct usage telegraf
telegraf --test
EOF

}

while [ $# -gt 0 ]; do
    case $1 in
        -dbs | --databases)
            while [ "$2" != "-dbs" ] && [ "$2" != "--databases" ] && [ "$2" != "-h" ] && [ "$2" != "--host" ] && [ "$2" != "-p" ] && [ "$2" != "--port" ] && [ $# -gt 0 ]; do
                if [ "$2" == "-n" ] || [ "$2" == "--name" ]; then
                    if [ ! -z "$3" ] && [ "${3:0:1}" != "-" ]; then INFLUX_DB_NAME="$3"; fi
                    if [ "$4" == "-t" ] || [ "$4" == "--timeback" ]; then
                        if [ ! -z "$5" ] && [ "${5:0:1}" != "-" ] && [[ "$5" =~ ^[0-9]+$ ]]; then INFLUX_TIME_BACK="$5"; fi
                    elif [ "$4" == "-r" ] || [ "$4" == "--rotate" ]; then
                        if [ ! -z "$5" ] && [ "${5:0:1}" != "-" ] && [[ "$5" =~ ^[0-9]+$ ]]; then INFLUX_BACKUP_ROT="$5"; fi
                    fi
                    if [ "$6" == "-r" ] || [ "$6" == "--rotate" ]; then
                        if [ ! -z "$7" ] && [ "${7:0:1}" != "-" ] && [[ "$7" =~ ^[0-9]+$ ]]; then INFLUX_BACKUP_ROT="$7"; fi
                    elif [ "$6" == "-t" ] || [ "$6" == "--timeback" ]; then
                        if [ ! -z "$7" ] && [ "${7:0:1}" != "-" ] && [[ "$7" =~ ^[0-9]+$ ]]; then INFLUX_TIME_BACK="$7"; fi
                    fi
                fi
                if [ ! -z "$INFLUX_DB_NAME" ]; then
                    INFLUX_DBS+=("$INFLUX_DB_NAME|$INFLUX_TIME_BACK|$INFLUX_BACKUP_ROT")
                    INFLUX_DB_NAME=; INFLUX_TIME_BACK=; INFLUX_BACKUP_ROT=;
                fi
                shift
            done
            ;;
        -h | --host)
            INFLUX_HOST="$2"
            shift
            ;;
        -p | --port)
            INFLUX_PORT="$2"
            shift
            ;;
        --help)
            f_usage
            exit 0
            ;;
        --recovery)
            f_recovery
            exit 0
            ;;
        *)
            f_usage
            exit 1
    esac
    shift
done

if [ -z $INFLUX_DBS ] || [ -z $INFLUX_HOST ] || [ -z $INFLUX_PORT ] || [[ ! "$INFLUX_PORT" =~ ^[0-9]+$ ]]; then
    echo "You must set all required params for execute this script."
    echo "See --help for more information."
    exit 1
fi

if [ ! -d "$INFLUX_BACKUP_DIR" ]; then mkdir -p "$INFLUX_BACKUP_DIR"; fi
exec &> >(tee -a $INFLUX_BACKUP_LOG)

f_check_free_disk_space $INFLUX_BACKUP_DISK $INFLUX_BACKUP_DISK_THRESHOLD

if [ $? -ne 0 ]; then
    f_elapsed_time; INFLUX_BACKUP_RES="Threshold free disk space in $INFLUX_BACKUP_DISK < $INFLUX_BACKUP_DISK_THRESHOLD% ($ELAPSED_TIME)."; f_logger "FAIL" "$INFLUX_BACKUP_RES"
    echo -en "\\033[1;34m"; echo -en $INFLUX_BACKUP_RES; echo -en "\\033[0;39m"; echo -e
    if [ "$MAIL_VERBOSE" = "FAIL_OK" ] || [ "$MAIL_VERBOSE" = "ONLY_FAIL" ]; then f_mailer "FAIL" "$INFLUX_BACKUP_RES" | $(which telnet) $MAILSERVER $MAILPORT; fi
    exit 1
fi

SAVEIFS=$IFS; IFS=$(echo -en "\n\b")
for ITEM in ${INFLUX_DBS[*]}; do
    if [ ! -z $ITEM ]; then
        INFLUX_DB_NAME=$(echo $ITEM | cut -d "|" -f 1); INFLUX_TIME_BACK=$(echo $ITEM | cut -d "|" -f 2); INFLUX_BACKUP_ROT=$(echo $ITEM | cut -d "|" -f 3)
        echo -en "\\033[0;90m"; echo -en "---------------------------------------------------------------------------------------------------"; echo -en "\\033[0;39m"; echo -e
        echo -en "\\033[0;1m"; echo -en "db name:             "; echo -en "\\033[0;100m"; echo -en "$INFLUX_DB_NAME"; echo -en "\\033[0;39m"; echo -e
        echo -en "\\033[0;1m"; echo -en "time back (minutes): "; echo -en "\\033[0;100m"; echo -en "$INFLUX_TIME_BACK"; echo -en "\\033[0;39m"; echo -e
        echo -en "\\033[0;1m"; echo -en "retention (minutes): "; echo -en "\\033[0;100m"; echo -en "$INFLUX_BACKUP_ROT"; echo -en "\\033[0;39m"; echo -e
        echo -en "\\033[0;1m"; echo -en "host:                "; echo -en "\\033[0;100m"; echo -en "$INFLUX_HOST"; echo -en "\\033[0;39m"; echo -e
        echo -en "\\033[0;1m"; echo -en "port:                "; echo -en "\\033[0;100m"; echo -en "$INFLUX_PORT"; echo -en "\\033[0;39m"; echo -e
        echo
        if [ ! -z $INFLUX_DB_NAME ] && [ -z $INFLUX_TIME_BACK ]; then
            f_backup_influxdb "$INFLUX_DB_NAME" "$INFLUX_HOST" "$INFLUX_PORT"
        elif [ ! -z $INFLUX_DB_NAME ] && [ ! -z $INFLUX_TIME_BACK ]; then
            f_backup_influxdb "$INFLUX_DB_NAME" "$INFLUX_HOST" "$INFLUX_PORT" "$INFLUX_TIME_BACK"
        fi
        if [ $? -ne 0 ]; then
            f_elapsed_time; INFLUX_BACKUP_RES="INFLUX backup for database $INFLUX_DB_NAME failed ($ELAPSED_TIME)."; f_logger "FAIL" "$INFLUX_BACKUP_RES"
            echo -en "\n"; echo -en "\\033[0;1m"; echo -en "result: "; echo -en "\\033[0;31m"; echo -en $INFLUX_BACKUP_RES; echo -en "\\033[0;39m"; echo -e
            if [ "$MAIL_VERBOSE" = "FAIL_OK" ] || [ "$MAIL_VERBOSE" = "ONLY_FAIL" ]; then f_mailer "FAIL" "$INFLUX_BACKUP_RES" | $(which telnet) $MAILSERVER $MAILPORT; fi
        else
            f_elapsed_time; INFLUX_BACKUP_RES="INFLUX backup for database $INFLUX_DB_NAME completed successfully ($ELAPSED_TIME)."; f_logger "OK" "$INFLUX_BACKUP_RES"
            echo -en "\n"; echo -en "\\033[0;1m"; echo -en "result: "; echo -en "\\033[0;32m"; echo -en $INFLUX_BACKUP_RES; echo -en "\\033[0;39m"; echo -e
            if [ "$MAIL_VERBOSE" = "FAIL_OK" ] || [ "$MAIL_VERBOSE" = "OK" ]; then f_mailer "OK" "$INFLUX_BACKUP_RES" | $(which telnet) $MAILSERVER $MAILPORT; fi
            if [ ! -z "$INFLUX_BACKUP_ROT" ] && [[ "$INFLUX_BACKUP_ROT" =~ ^[0-9]+$ ]]; then f_rotate "$INFLUX_BACKUP_DIR" "$INFLUX_DB_NAME" "$INFLUX_BACKUP_ROT"; fi
        fi
    fi
done
IFS=$SAVEIFS
