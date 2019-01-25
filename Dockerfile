FROM ubuntu:16.04

RUN apt-get update -y && apt-get upgrade -y

# minimum package required for working inside a container
RUN apt-get install -y curl gnupg net-tools iputils-ping nmap python-pip python-dev sudo vim

# package for installing Metasploit Framework
RUN apt-get install -y build-essential zlib1g zlib1g-dev libxml2 libxml2-dev \
    libxslt-dev locate libreadline6-dev libcurl4-openssl-dev git-core libssl-dev \
    libyaml-dev openssl autoconf libtool ncurses-dev bison wget \
    libpq-dev libapr1 libaprutil1 libsvn1 libpcap-dev

# make the user who can work as root without password.
ENV USER msf_user
ENV HOME /home/${USER}
ENV SHELL /bin/bash
RUN useradd -m ${USER}
RUN gpasswd -a ${USER} sudo
RUN echo "${USER}:msf_pass" | chpasswd
RUN sed -i.bak "s#${HOME}:#${HOME}:${SHELL}#" /etc/passwd
ADD ./config/sudoers.txt /etc/sudoers
RUN chmod 440 /etc/sudoers
USER ${USER}

# install Metasploit Framework
RUN cd /tmp  && \
    curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && \
    chmod 777 msfinstall && \
    ./msfinstall && \
    sudo chown -R `whoami` /opt/metasploit-framework

# EXPOSE
EXPOSE 5432/tcp

# settings for PostgreSQL. refer http://docs.docker.jp/engine/examples/postgresql_service.html
# Add the PostgreSQL PGP key to verify their Debian packages.
# It should be the same key as https://www.postgresql.org/media/keys/ACCC4CF8.asc
USER root
RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8 && \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && apt-get install -y python-software-properties software-properties-common postgresql-9.3 postgresql-client-9.3 postgresql-contrib-9.3

USER ${USER}
RUN mkdir /home/${USER}/.msf4/
COPY ./config/database.yml /home/${USER}/.msf4/database.yml

# settings for using Metasploit Framework easily.
USER root
RUN mv /bin/sh /bin/sh_tmp && ln -s /bin/bash /bin/sh
RUN sh -c "echo export MSF_DATABASE_CONFIG=/opt/metasploit-framework/config/database.yml >> /etc/profile"
RUN source /etc/profile
RUN rm /bin/sh && mv /bin/sh_tmp /bin/sh

# Create a PostgreSQL role named ``msf_user`` with ``msf_pass`` as the password and
# then create a database `msf_database` owned by the ``msf_user`` role.
USER postgres
RUN  /etc/init.d/postgresql start &&\
    psql --command "CREATE USER msf_user WITH SUPERUSER PASSWORD 'msf_pass';" &&\
    createdb --owner=msf_user msf_database

# Adjust PostgreSQL configuration so that remote connections to the
# database are possible.
USER root
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/9.3/main/pg_hba.conf
RUN echo "listen_addresses='*'" >> /etc/postgresql/9.3/main/postgresql.conf

USER postgres

# Add VOLUMEs to allow backup of config, logs and databases
VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]

# Set the default command to run when starting the container
CMD ["/usr/lib/postgresql/9.3/bin/postgres", "-D", "/var/lib/postgresql/9.3/main", "-c", "config_file=/etc/postgresql/9.3/main/postgresql.conf"]

USER ${USER}
ENTRYPOINT sudo service postgresql start && /bin/bash
WORKDIR /opt/metasploit-framework/
