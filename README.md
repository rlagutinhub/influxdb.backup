# Influxdb OSS backup and restore
```console
Available options for influxdb backup script:

 -dbs | --databases   Sets list of databases to back up with the following parameters:

     -n | --name      - database name for backup
     -t | --timeback  - number of minutes ago, where the backup will include all data
                        from the current time minus the specified number of minutes to the current time.
                        if not set, then full backup!
     -r | --rotate    - Sets number of minutes to keep backup before rotate.

 -h | --host            Sets influxdb host.
 -p | --port            Sets influxdb port.

 --help                 Shows this help output.
 --recovery             Shows plan of disaster recovery.

Note: Do not backup for db _internal, because it cannot be recovered from this backup.

 Example: ./influxdb.backup.sh -dbs -n "telegraf" -t 43200 -r 43200 -n "chronograf" -r 43200 -h "localhost" -p 8088
```

## Disaster recovery
* https://docs.influxdata.com/influxdb/v1.7/administration/backup_and_restore/
* https://www.influxdata.com/blog/new-features-in-open-source-backup-and-restore/

Important: If after restored status of clients is offline and they not sending new data, that is failed restore influxdb data!!!

#### before required
```
systemctl stop kapacitor.service
systemctl stop chronograf.service
systemctl stop grafana-server.service
systemctl stop nginx.service
```
#### clear influxdb config
```
systemctl stop influxdb.service
rm -rf /var/lib/influxdb/*
systemctl start influxdb.service
```
#### create admin user
```
influx
CREATE USER "admin" WITH PASSWORD 'your-password' WITH ALL PRIVILEGES
exit
```
#### check admin user
```
influx -username 'admin' --password '' -host 'localhost'
SHOW USERS
exit
```
#### restore db telegraf (include retention policys and all shards)
```
influxd restore -portable -db telegraf -host localhost:8088 path-to-backup
```
#### restore db chronograf (include retention policys and all shards)
```
influxd restore -portable -db chronograf -host localhost:8088 path-to-backup
```
#### check restored db
```
influx -username 'admin' --password '' -host 'localhost'
SHOW DATABASES
exit
```
#### manual restore security
```
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
```
#### after required
```
systemctl restart influxdb.service
systemctl start kapacitor.service
systemctl start chronograf.service
systemctl start grafana-server.service
systemctl start nginx.service
```
#### troubleshooting client (after restore)

1. in chronograf status for this client - offline
```
journalctl --full -u telegraf.service
[outputs.influxdb] when writing to [http://influxdb.example.com:8086]: 403 Forbidden: "telegraf" user is not authorized to write to database "telegraf"
[agent] Error writing to output [influxdb]: could not write any address

systemctl restart telegraf.service # resolve
```
2. check connection telegraf to influxdb
```
curl -k -i http://influxdb.example.com:8086/ping # ok if return 204
```

3. check correct usage telegraf
```
telegraf --test
```

---

![alt text](https://github.com/rlagutinhub/influxdb.backup/blob/master/screen.png)
