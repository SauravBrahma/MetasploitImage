FROM ubuntu:16.04

RUN apt-get update -y && apt-get upgrade -y

# コンテナ内で作業するために必要な最低限のパッケージ
RUN apt-get install -y curl gnupg net-tools iputils-ping nmap python-pip python-dev sudo vim

# Metasploit Frameworkのために必要なパッケージをインストール
RUN apt-get install -y build-essential zlib1g zlib1g-dev libxml2 libxml2-dev \
    libxslt-dev locate libreadline6-dev libcurl4-openssl-dev git-core libssl-dev \
    libyaml-dev openssl autoconf libtool ncurses-dev bison wget \
    libpq-dev libapr1 libaprutil1 libsvn1 libpcap-dev

# コンテナ内でパスワードなしでrootになれるユーザを作成，また，このDockerfileの中でもsudoを使う事が可能
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

# Metasploit Frameworkをインストール
RUN cd /tmp  && \
    curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && \
    chmod 777 msfinstall && \
    ./msfinstall && \
    sudo chown -R `whoami` /opt/metasploit-framework

# ポートをEXPOSE
EXPOSE 5432/tcp

# PostgreSQL関連の設定．http://docs.docker.jp/engine/examples/postgresql_service.htmlを参照
# PostgreSQLのPGPキーを追加してDebianパッケージを検証．これはhttps://www.postgresql.org/media/keys/ACCC4CF8.ascと同じ鍵である必要がある
USER root
RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8 && \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && apt-get install -y python-software-properties software-properties-common postgresql-9.3 postgresql-client-9.3 postgresql-contrib-9.3

USER ${USER}
RUN mkdir /home/${USER}/.msf4/
COPY ./config/database.yml /home/${USER}/.msf4/database.yml

# Metasploit Frameworkを楽に使用するための環境変数の設定
USER root
RUN mv /bin/sh /bin/sh_tmp && ln -s /bin/bash /bin/sh
RUN sh -c "echo export MSF_DATABASE_CONFIG=/opt/metasploit-framework/config/database.yml >> /etc/profile"
RUN source /etc/profile
RUN rm /bin/sh && mv /bin/sh_tmp /bin/sh

# ユーザ名：’msf_user’，パスワード：’msf_pass’でPostgreSQLのロールを作成し，
# データベース名：’msf_database’，所有ユーザ：’msf_user’のデータベースを作成
USER postgres
RUN  /etc/init.d/postgresql start &&\
    psql --command "CREATE USER msf_user WITH SUPERUSER PASSWORD 'msf_pass';" &&\
    createdb --owner=msf_user msf_database

# データベースへのリモート接続が可能なようにPostgreSQLの設定を調整
USER root
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/9.3/main/pg_hba.conf
RUN echo "listen_addresses='*'" >> /etc/postgresql/9.3/main/postgresql.conf

USER postgres

# 設定、ログ、データベースのバックアップを可能にするVOLUMEを追加
VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]

# コンテナ起動時に送るデフォルトのコマンドを設定
CMD ["/usr/lib/postgresql/9.3/bin/postgres", "-D", "/var/lib/postgresql/9.3/main", "-c", "config_file=/etc/postgresql/9.3/main/postgresql.conf"]

USER ${USER}
ENTRYPOINT sudo service postgresql start && /bin/bash
WORKDIR /opt/metasploit-framework/

