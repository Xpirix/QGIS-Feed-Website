# ✨ Contributing to QGIS-Feed

Thank you for considering contributing to QGIS Feed!
We welcome contributions of all kinds, including bug fixes, feature requests,
documentation improvements, and more. Please follow the guidelines below to
ensure a smooth contribution process.

![-----------------------------------------------------](./img/green-gradient.png)


## 🧑💻 Development

For development purposes only, you can run this application in debug mode with docker compose. Some of the docker compose commands are already configured in the Makefile.

## 🏃Before you start

This project requires [Docker](https://www.docker.com/) and [Docker Compose](https://docs.docker.com/compose/) to run the development and production environments.
Please ensure both are installed on your system before proceeding.

![Docker logo](https://www.docker.com/wp-content/uploads/2022/03/Moby-logo.png)

You can check your installation with:
```bash
docker --version
docker-compose --version
```

![-----------------------------------------------------](./img/green-gradient.png)

## 🛒 Getting the Code

- Clone git repo `git clone https://github.com/qgis/QGIS-Feed-Website.git`
- Run `$ pwd` in order to get your current directory
- Path to your repo should be `<your current directory>/QGIS-Feed-Website `
- Go to dockerize directory `cd QGIS-Feed-Website`

![-----------------------------------------------------](./img/green-gradient.png)

## Pre-commit hooks

This repository uses [pre-commit](https://pre-commit.com/) to automate code quality checks before each commit. To set it up:

1. Install pre-commit (if not already installed):
    ```sh
    pip install pre-commit
    ```

2. Install the hooks defined in `.pre-commit-config.yaml`:
    ```sh
    pre-commit install
    ```

Now, the configured checks (such as linting and formatting) will run automatically when you commit changes.

![-----------------------------------------------------](./img/green-gradient.png)


### ❄️ Nix

The flake provides a complete development environment: Python, Node, and a
project-local PostgreSQL/PostGIS cluster. **Docker is not required** if you
develop this way.

```sh
nix develop                     # enter the environment (direnv users: just `cd` in)
./scripts/nix/db-start.sh       # start the local PostgreSQL/PostGIS
./scripts/nix/db-reset.sh       # create the schema and load the fixtures
./scripts/nix/fetch-geoip.sh    # download the GeoLite2 City database (once)
./scripts/nix/dev.sh            # webpack watch + Django dev server on :8000
```

Then open <http://localhost:8000>. The fixtures create the same users as the
docker path.

#### Commands

Run the helpers directly when you are inside `nix develop`; every tool they need
is already on `PATH`. The `nix run` column is for invoking them from an ordinary
shell without entering the environment first.

| Inside `nix develop` | From outside | Description |
|---|---|---|
| `./scripts/nix/db-start.sh` | `nix run .#db-start` | Start the local PostgreSQL/PostGIS cluster |
| `./scripts/nix/db-stop.sh` | `nix run .#db-stop` | Stop it |
| `./scripts/nix/db-reset.sh` | `nix run .#db-reset` | Drop and recreate the DB, migrate, load fixtures (prompts first) |
| `./scripts/nix/db-restore.sh` | `nix run .#db-restore` | Restore the DB from a `pg_dump` archive (prompts first) |
| `./scripts/nix/manage.sh <cmd>` | `nix run .#manage -- <cmd>` | Run any Django management command |
| `./scripts/nix/dev.sh` | `nix run .#dev` | Run webpack in watch mode plus the Django dev server |
| `./scripts/nix/test.sh` | `nix run .#test` | Run the Django test suite |
| `./scripts/nix/fetch-geoip.sh` | `nix run .#fetch-geoip` | Download `GeoLite2-City.mmdb` |
| — | `nix flake check` | Evaluate every output and run the checks |
| — | `nix fmt` | Format the Nix files |

Both columns work from anywhere; the script form simply skips a flake
re-evaluation on every call.

#### How it is put together

- **State** lives in `.nix/` (git-ignored): the PostgreSQL cluster in
  `.nix/pgdata`, its socket in `.nix/run`, the GeoIP database in `.nix/geoip`.
  Delete the directory to start over.
- **The database** is an unprivileged cluster owned by you, listening on a unix
  socket inside the repository only. Nothing is bound to a network interface,
  so it cannot clash with a system PostgreSQL.
- **Settings** come from `qgisfeedproject/settings_nix.py`. It inherits
  `settings.py`, whose `DATABASES` block is already environment driven;
  `scripts/nix/common.sh` points `QGISFEED_DOCKER_DBHOST` at the local socket.
  (`settings_dev.py` is not reused because it hardcodes `HOST = "postgis"`,
  which only exists inside the docker compose network.)
- **Python dependencies** come from nixpkgs, except three that nixpkgs cannot
  supply at the version this project needs; those are built from real
  derivations in `nix/python-packages.nix`. There is no pip step and no
  virtualenv.
- **nixpkgs** is pinned centrally for all QGIS repositories via
  [qgis-nixpkgs-version](https://github.com/QGIS/qgis-nixpkgs-version). Bump it
  there, not here.
- **Shell helpers** are ordinary scripts in `scripts/nix/`, wrapped by the
  flake. Nothing but wiring lives in the `.nix` files.

#### Configuration (`.env`)

`scripts/nix/common.sh` reads the same git-ignored `.env` that docker compose
uses, so site configuration is defined once. `env.template` is the committed
reference. To add a variable, put it in `env.template` and in your `.env`; the
Nix helpers pick it up with no further wiring.

Precedence is **explicit shell environment > `.env` > built-in defaults**, so a
one-off override works:

```sh
QGISFEED_BACKUP_VOLUME=/mnt/other ./scripts/nix/db-restore.sh
```

The file is parsed rather than sourced, so nothing in it is executed.

Docker-only keys are ignored by the Nix path — importing them would point it at
the docker database role and at the docker settings override, which hardcodes
`MEDIA_ROOT=/shared-volume/media` and fails outside a container. The ignore list
is `_qgisfeed_env_is_docker_only` in `scripts/nix/common.sh`.

Note that `.env` also carries SMTP and social-media credentials. Loading it
exports those into your development shell, exactly as it does for docker
compose. Production does not use this path at all: the NixOS module passes
secrets via `EnvironmentFile` so they never enter the Nix store.

#### GeoIP data

The geofence feature needs `GeoLite2-City.mmdb`, which is MaxMind licensed and
therefore not committed or vendored. `./scripts/nix/fetch-geoip.sh` downloads it into
`.nix/geoip/`. Without it, location lookups silently return no result.

#### Deployment

`nix build` produces the application closure, and `nixosModules.qgisfeed`
provides a systemd service for NixOS hosts. PostgreSQL and Metabase are
supplied by the surrounding infrastructure, so the module configures the Django
instance only. Secrets - including `QGISFEED_SECRET_KEY`, which **must not** be
the development value in `settings.py` - are passed through
`services.qgisfeed.environmentFile`, never through Nix options, because
everything in the Nix store is world readable.

### ⚡️ Quick Start
- Build the docker the container
```bash
$ make dev-build
```

#### Environment setup
- Create `settings_local.py` int the `qgisfeedproject` directory, configure the media folder as in the example below:

```python
# Settings local for docker compose production settings
import os

MEDIA_ROOT = '/shared-volume/media/'
MEDIA_URL = '/media/'
STATIC_ROOT = '/shared-volume/static/'
STATIC_URL = '/static/'


if not os.path.exists(MEDIA_ROOT):
    os.mkdir(MEDIA_ROOT)

if not os.path.exists(STATIC_ROOT):
    os.mkdir(STATIC_ROOT)
```

- Generate the `.env` from `env.template` and edit it with your email variables:
```sh
cp env.template .env
nano .env
```
Don't forget to specify the QGISFEED_MEDIA_VOLUME with your media directory

See https://docs.djangoproject.com/en/2.2/topics/email/#module-django.core.mail for further email configuration.

- To prevent DDOS attacks there is limit in the number of returned records (defaults to 20): it can be configured by overriding the settings in `settings_local.py` with:

```python
QGISFEED_MAX_RECORDS=40  # default value is 20
```

**IMPORTANT NOTE**: For new Django variables, please use the `settings_local_override.py` as the `.env` file is not supported by the new production infrastructure.

#### Django Local Settings Override (`settings_local_override.py`)

- Create settings_local_override.py file
```bash
$ cp settings_local_override.py.templ settings_local_override.py
```

- Edit settings_local_override.py file and set your environment variables

**IMPORTANT NOTE**: As we are migrating to a declarative based infrastructure, it is preferable to use the `settings_local_override.py` file for all new Django variables. This file is ignored when commiting so please make sure you define your new variables with an example value (**NOT THE REAL ONE FOR SECRETS AND PASSWORDS**) inside the `settings_local_override.py.templ` file.

#### Spin up the development environment

- Start the docker the container
```bash
$ make dev-start
```

- Run migrations:
```bash
$ make dev-migrate
```

- Create an admin user and set a password:
```bash
$ make dev-createsuperuser
```

- Show the development server logs:
```bash
$ make dev-logs
```


A set of test data will be automatically loaded and the application will be available at http://localhost:8000

To enter the control panel http://localhost:8000/admin, two test users are available:

- Super Admin: the credentials are `admin`/`admin`
- Staff (News Entry Author): the credentials are `staff`/`staff`

</details>


![-----------------------------------------------------](./img/green-gradient.png)

## 🧪 Running Django Unit Tests
<details>
    <summary><strong>🧪 Run all tests</strong></summary>
        </br>

To run all tests cases in the qgisfeed app, from the main directory:
```sh
$ make dev-runtests
```
</details>

<details>
    <summary><strong>🧪 Run a specific test</strong></summary>
        </br>

To run each test case class in the qgisfeed app:
```sh
$ docker-compose -f docker-compose.dev.yml exec qgisfeed python qgisfeedproject/manage.py test qgisfeed.tests.QgisFeedEntryTestCase
$ docker-compose -f docker-compose.dev.yml exec qgisfeed python qgisfeedproject/manage.py test qgisfeed.tests.QgisUserVisitTestCase
$ docker-compose -f docker-compose.dev.yml exec qgisfeed python qgisfeedproject/manage.py test qgisfeed.tests.HomePageTestCase
$ docker-compose -f docker-compose.dev.yml exec qgisfeed python qgisfeedproject/manage.py test qgisfeed.tests.LoginTestCase
$ docker-compose -f docker-compose.dev.yml exec qgisfeed python qgisfeedproject/manage.py test qgisfeed.tests.FeedsItemFormTestCase
$ docker-compose -f docker-compose.dev.yml exec qgisfeed python qgisfeedproject/manage.py test qgisfeed.tests.FeedsListViewTestCase
```
</details>

## 🚀 Production Environment


<details>
    <summary><strong>⚙️ Production Environment Installation</strong></summary>
    </br>
For production, you can run this application with make commands or docker compose:

Docker configuration should be present in `.env` file in the main directory,
an example is provided in `env.template`:

```bash
# This file can be used as a template for .env
# The values in this file are also the default values.

# Host machine persistent storage directory, this path
# must be an existent directory with r/w permissions for
# the users from the Docker containers.
QGISFEED_DOCKER_SHARED_VOLUME=/shared-volume

# Number of Gunicorn workers (usually: number of cores * 2 + 1)
QGISFEED_GUNICORN_WORKERS=4

# Database name
QGISFEED_DOCKER_DBNAME=qgisfeed
# Database user
QGISFEED_DOCKER_DBUSER=docker
# Database password
QGISFEED_DOCKER_DBPASSWORD=docker
```

```bash
$ make start
```

A set of test data will be automatically loaded and the application will be available at http://localhost:80

To enter the control panel http://localhost:80/admin, two test users are available:

- Super Admin: the credentials are `admin`/`admin`
- Staff (News Entry Author): the credentials are `staff`/`staff`

### Enable SSL Certificate on production using Docker

1. Generate key using openssl in dhparam directory
```bash
openssl dhparam -out /home/web/qgis-feed/dhparam/dhparam-2048.pem 2048
```

2. Run the container
```bash
$ make start
```

3. Update `config/nginx/qgisfeed.conf` to include the new config file in `config/nginx/ssl/qgisfeed.conf`
```
include conf.d/ssl/*.conf;
```

4. Restart nginx service
```
nginx -s reload
```

5. To enable a cronjob to automatically renew ssl cert, add `scripts/renew_ssl.sh` to crontab file.

</details>

<details>
    <summary><strong>📧 Email-sending setup</strong></summary>
    </br>


- Generate the `.env` from `env.template` and edit it with the production email variables:
```sh
cp env.template .env
nano .env
```

</details>

<details>
    <summary><strong>🛠️ Troubleshooting SSL in production</strong></summary>
        </br>

Sometimes it seems our cron does not refresh the certificate. We can fix like this:

**Gentle Way**

```
ssh feed.qgis.org
cd /home/web/qgis-feed
scripts/renew_ssl.sh
```

Now check if your browser is showing the site opening with no SSL errors: https://feed.qgis.org

**More crude way**

```
ssh feed.qgis.org
cd /home/web/qgis-feed
make start c=certbot
make restart c=nginx
```

Now check if your browser is showing the site opening with no SSL errors: https://feed.qgis.org

</details>

> Please visit the private Sysadmin documentation for more details about the deployment of https://feed.qgis.org

![-----------------------------------------------------](./img/green-gradient.png)


## Backups

If something goes terribly wrong, we keep 7 nights of backups on hetzner and daily backups on a storage box.

If those are also not useful there are a collection of snapshot backups on hetzner and on a storage box

Last resort: Tim and Lova makes backups to his local machine on a semi-regular basis.


![-----------------------------------------------------](./img/green-gradient.png)
