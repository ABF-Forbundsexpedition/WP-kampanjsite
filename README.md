# WP-kampanjsite

Docker-baserad drift av WordPress-kampanjsiter på **abf000webu2.abf.se**.
Varje site bor i sin egen mapp under `/home/WP/<domän>/` med egna containrar
(WordPress + MariaDB), egna lösenord och egen nginx-vhost med TLS.

```
webu2
├─ nginx + certbot (på värden)  →  domän → 127.0.0.1:<port>
└─ /home/WP/<domän>/               en mapp per site (klon av detta repo)
   ├─ docker-compose.yml           wordpress + mariadb + sftp (+ wp-cli)
   ├─ .env                         genererade lösenord, portar, domän
   ├─ site-info.txt                kontoblad (skapas av newsite.sh)
   ├─ ssh/                         sftp-containerns värdnycklar
   ├─ wp-content/                  teman, plugins, uppladdningar (= SFTP)
   └─ db-data/                     databasens filer
```

Varje site får en egen SFTP-ingång (egen container, egen port) där
användaren är chrootad och bara ser sitens `wp-content` – de kan ladda
upp teman och filer men inte röra WordPress-kärnan eller andra siter.

## Förutsättningar

- DNS: ett CNAME på domänen som pekar mot `abf000webu2.abf.se`
  (vilken domän som helst fungerar).
- På servern: `nginx`, `certbot` (med nginx-plugin), `docker` med
  compose, `git`, `openssl`.
- Brandvägg: portarna **80, 443** samt SFTP-intervallet **20001–20999**
  öppna in mot servern.
- Detta repo klonat en gång som mall: `/home/WP/WP-kampanjsite`.

## Skapa en ny site

```bash
cd /home/WP/WP-kampanjsite
sudo bash ./newsite.sh kampanj.example.se info@abf.se
```

Skriptet väljer nästa lediga portpar själv (webb 8001+, sftp 20001+),
genererar alla lösenord, ordnar nginx + certifikat och installerar
WordPress på svenska med en admin-användare. Kontobladet med alla
uppgifter – inklusive användarens SFTP-inloggning – skrivs ut och
sparas i `/home/WP/kampanj.example.se/site-info.txt`. Det är allt som
behöver lämnas över till användaren.

Utelämnas e-postadressen installeras inte WordPress automatiskt –
då körs installationsguiden i webbläsaren vid första besöket.

## Administrera en site

Alla kommandon körs i sitens mapp, t.ex. `/home/WP/kampanj.example.se`:

| Uppgift | Kommando |
|---|---|
| wp-cli (valfritt kommando) | `sudo bash ./wp.sh plugin list` |
| Nytt admin-lösenord | `sudo bash ./wp.sh user update admin --user_pass=NyttLösen` |
| Backup nu | `sudo bash ./backup.sh` |
| Starta om | `sudo docker compose restart` |
| Loggar | `sudo docker compose logs -f wordpress` |

Översikt över alla siter: `sudo bash /home/WP/WP-kampanjsite/listsites.sh`

## Backup

Nattlig backup av alla siter (databas-dump + wp-content, 14 dagars
rotation) – lägg i root:s crontab:

```
30 3 * * * /home/WP/WP-kampanjsite/backup-all.sh >> /var/log/wp-backup.log 2>&1
```

Backuper hamnar i `/home/WP/backups/<domän>/`.

**Återställning:** packa upp `wp-content`-tarballen i sitens mapp och
läs in dumpen: `zcat db-XXX.sql.gz | sudo docker compose exec -T db sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" wordpress'`

## Ta bort en site

```bash
cd /home/WP/kampanj.example.se
sudo bash ./removesite.sh      # tar sista backup, frågar om bekräftelse
sudo rm -rf /home/WP/kampanj.example.se   # när backupen är kontrollerad
```

**OBS:** kör aldrig `docker container prune` / `docker volume prune` på
servern – det raderar data som tillhör andra siter.

## Versionshantering

Repots version står i filen `VERSION` – **bumpa den vid varje ändring
av mallen** och pusha till GitHub.

`newsite.sh` och `setup.sh` kontrollerar automatiskt mot origin innan
de kör (mallen jämför mot GitHub, en site jämför mot mallen) och
frågar om uppdatering ska göras först om en nyare version finns.
Vid icke-interaktiv körning uppdateras inget – då visas bara en notis.

Uppdatera en befintlig site till mallens senaste version:

```bash
cd /home/WP/kampanj.example.se
sudo bash ./setup.sh     # upptäcker ny version, frågar, uppdaterar och kör om
```

`listsites.sh` visar vilken version varje site ligger på.

## Uppdatera WordPress/PHP-version

Image-versionerna är medvetet låsta i `docker-compose.yml`
(`wordpress:6.8-php8.3-apache`, `mariadb:10.11`) så att siter inte
hoppar versioner okontrollerat. Vid uppgradering: ta backup, ändra
taggen i sitens `docker-compose.yml`, kör
`sudo docker compose pull && sudo docker compose up -d` och verifiera.
Uppdatera även mallen (detta repo) så nya siter får rätt version.

## Äldre siter (skapade före denna version)

Siter som skapats med den gamla mallen (`wordpress:latest`,
`mysql:latest`, port publicerad på alla interface) fortsätter fungera
men bör migreras: lås image-taggarna till dem som faktiskt körs
(`docker compose images`), och ändra `ports:` till
`'127.0.0.1:<port>:80'`. Byt inte databas-image på en befintlig site
utan dump + import.
