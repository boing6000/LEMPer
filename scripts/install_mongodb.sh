#!/usr/bin/env bash

# MongoDB installer
# Ref : https://www.linode.com/docs/databases/mongodb/install-mongodb-on-ubuntu-16-04
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 01/08/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function add_mongodb_repo() {
    echo "Adding MongoDB ${MONGODB_VERSION} repository..."

    MONGODB_VERSION=${MONGODB_VERSION:-"4.0"}
    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}
    local DISTRIB_ARCH

    case ${ARCH} in
        x86_64)
            DISTRIB_ARCH="amd64"
        ;;
        i386|i486|i586|i686)
            DISTRIB_ARCH="i386"
        ;;
        armv8)
            DISTRIB_ARCH="arm64"
        ;;
        *)
            DISTRIB_ARCH="amd64,i386"
        ;;
    esac

    case ${DISTRIB_NAME} in
        debian)
            [[ ${RELEASE_NAME} == "buster" ]] && local RELEASE_NAME="stretch"

            if [ ! -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" ]; then
                run touch "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "echo 'deb [ arch=${DISTRIB_ARCH} ] https://repo.mongodb.org/apt/debian ${RELEASE_NAME}/mongodb-org/${MONGODB_VERSION} main' > /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "wget -qO - 'https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc' | apt-key add -"
                run apt-get -qq update -y
            else
                warning "MongoDB ${MONGODB_VERSION} repository already exists."
            fi
        ;;
        ubuntu)
            if [ ! -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" ]; then
                run touch "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "echo 'deb [ arch=${DISTRIB_ARCH} ] https://repo.mongodb.org/apt/ubuntu ${RELEASE_NAME}/mongodb-org/${MONGODB_VERSION} multiverse' > /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "wget -qO - 'https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc' | apt-key add -"
                run apt-get -qq update -y
            else
                warning "MongoDB ${MONGODB_VERSION} repository already exists."
            fi
        ;;
        *)
            error "Unable to add MongoDB, unsupported distribution release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
            echo "Sorry your system is not supported yet, installing from source may fix the issue."
            exit 1
        ;;
    esac
}

function init_mongodb_install() {
    if "${AUTO_INSTALL}"; then
        DO_INSTALL_MONGODB="y"
    else
        while [[ "${DO_INSTALL_MONGODB}" != "y" && "${DO_INSTALL_MONGODB}" != "n" ]]; do
            read -rp "Do you want to install MongoDB? [y/n]: " -i n -e DO_INSTALL_MONGODB
        done
    fi

    if [[ ${DO_INSTALL_MONGODB} == y* && ${INSTALL_MONGODB} == true ]]; then
        # Add repository.
        add_mongodb_repo

        echo "Installing MongoDB server and MongoDB PHP module..."

        if hash apt-get 2>/dev/null; then
            run apt-get -qq install -y libbson-1.0 libmongoc-1.0-0 mongodb-org mongodb-org-server \
                mongodb-org-shell mongodb-org-tools php-mongodb
            
            # Install PHP-MongoDB
            #install_php_mongodb
        elif hash yum 2>/dev/null; then
            if [ "${VERSION_ID}" == "5" ]; then
                yum -y update
                #yum -y localinstall mongodb-org mongodb-org-server --nogpgcheck
            else
                yum -y update
            	#yum -y localinstall mongodb-org mongodb-org-server
            fi
        else
            fail "Unable to install MongoDB, this GNU/Linux distribution is not supported."
        fi

        # Enable in start-up
        run systemctl enable mongod.service
        run systemctl restart mongod

        if "${DRYRUN}"; then
            warning "MongoDB server installed in dryrun mode."
        else
            echo "MongoDB installation completed."
            echo "After installation finished, you can add a MongoDB administrative user. Example command lines below:";
            cat <<- _EOF_

mongo
> use admin
> db.createUser({"user": "admin", "pwd": "<Enter a secure password>", "roles":[{"role": "root", "db": "admin"}]})
> quit()

mongo -u admin -p --authenticationDatabase user-data
> use exampledb
> db.createCollection("exampleCollection", {"capped": false})
> var a = {"name": "John Doe", "attributes": {"age": 30, "address": "123 Main St", "phone": 8675309}}
> db.exampleCollection.insert(a)
> WriteResult({ "nInserted" : 1 })
> db.exampleCollection.find()
> db.exampleCollection.find({"name" : "John Doe"})

_EOF_

            # Add MongoDB default admin user.
            if [[ -n $(command -v mongo) ]]; then
                MONGODB_ADMIN_USER=${MONGODB_ADMIN_USER:-"lemperdb"}
                MONGODB_ADMIN_PASS=${MONGODB_ADMIN_PASS:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
                run mongo admin --eval "db.createUser({'user': '${MONGODB_ADMIN_USER}', 'pwd': '${MONGODB_ADMIN_PASS}', 'roles':[{'role': 'root', 'db': 'admin'}]});" >/dev/null 2>&1

                # Save config.
                save_config -e "MONGODB_HOST=127.0.0.1\nMONGODB_PORT=27017\nMONGODB_ADMIN_USER=${MONGODB_ADMIN_USER}\nMONGODB_ADMIN_PASS=${MONGODB_ADMIN_PASS}"

                # Save log.
                save_log -e "MongoDB default admin user is enabled, here is your admin credentials:\nAdmin username: ${MONGODB_ADMIN_USER} | Admin password: ${MONGODB_ADMIN_PASS}\nSave this credentials and use it to authenticate your MongoDB connection."
            fi

            sleep 2
        fi
    else
        warning "MongoDB installation skipped..."
    fi
}

# Install PHP MongoDB module.
function install_php_mongodb() {
    echo "Installing PHP MongoDB module..."

    local CURRENT_DIR && \
    CURRENT_DIR=$(pwd)
    run cd "${BUILD_DIR}"

    run git clone --depth=1 -q https://github.com/mongodb/mongo-php-driver.git && \
    run cd mongo-php-driver && \
    run git submodule update --init

    if [[ -n "${PHP_VERSION}" ]]; then
        run "/usr/bin/phpize${PHP_VERSION}" && \
        run ./configure --with-php-config="/usr/bin/php-config${PHP_VERSION}"
    else
        run /usr/bin/phpize && \
        run ./configure
    fi

    run make all && \
    run make install && \
    run service "php${PHP_VERSION}-fpm" restart

    run cd "${CURRENT_DIR}"
}

echo "[MongoDB Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v mongod) ]]; then
    warning "MongoDB server already exists. Installation skipped..."
else
    init_mongodb_install "$@"
fi
