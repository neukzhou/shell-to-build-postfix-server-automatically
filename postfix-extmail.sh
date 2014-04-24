#! /bin/sh
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/home/$USER/bin
export PATH
#===============================================================================================
#   System Required:  CentOS5.x (64bit) or CentOS6.x (64bit)
#   Package Required:   EMOS-1.6 for x86_64
#   Description:  Installation & configuration of a MTA
#                   based on Postfix & Extmail for CentOS
#   Author: ZhouHao <zhouhao0925@gmail.com>
#   Intro:  http://zhouhao.me
#===============================================================================================

clear
echo "#############################################################"
echo "# MTA based on Postfix & Extmail for CentOS5.x (64bit) or CentOS6.x (64bit)"
echo "# Intro: http://zhouhao.me"
echo "#"
echo "# Author: ZhouHao <zhouhao0925@gmail.com>"
echo "#"
echo "#############################################################"
echo "" 

# Get Network Info
network=`ifconfig | grep eth | awk '{print $1}'`
net_num=`route -n | grep "U[ \t ].*\$network" | awk '{print $1}'`

mask=`ifconfig \$network |grep 'inet addr:' |grep -v '127.0.0.*' |cut -d:  -f4| awk '{print $1}'`
_mask=`echo ${mask} |awk -F'.' '{print ($1*(2^24)+$2*(2^16)+$3*(2^8)+$4)}'`
mask_bit=`echo "obase=2;${_mask}"|bc|awk -F'0' '{print length($1)}'`


# Install Shadowsocks
function install_postfix_extmail(){
    rootness
    disable_selinux
    download_package
    mount_iso
    local_yum
    install_postfix
    config_postfix
    install_courier_authlib
    install_maildrop
    config_apache
    config_extmail
    init_mysql
    graphic_log
    smtp_setting
    imap_setting
    off_iptables
    stat_update
}

# Make sure only root can run our script
function rootness(){
if [[ $EUID -ne 0 ]]; then
   echo "Error:This script must be run as root!" 1>&2
   exit 1
fi
}

# Disable selinux
function disable_selinux(){
if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi
}

# Download files
function download_package(){
    #directory for files setting
    myPath="/root/rpm"
    if [ -d "$myPath" ]; then
        cd "$myPath"
    else
        mkdir -p "$myPath"
        cd "$myPath"
    fi
    if [ -f EMOS_1.6_x86_64.iso ]; then
        echo "EMOS_1.6_x86_64.iso [found]"
    else
        echo "EMOS_1.6_x86_64.iso not found!!! Download now......"
        if ! wget --no-check-certificate http://mirror.extmail.org/iso/emos/EMOS_1.6_x86_64.iso;then
            echo "Fail to download EMOS_1.6_x86_64.iso!"
            exit 1
        fi
    fi
}

# Mount iso package
function mount_iso(){
    # Install createrepo
    if ! yum -y install createrepo; then
        echo "Fail to install createrepo!"
        exit 1
    fi

    # Mount iso
    myPath="/mnt/EMOS"
    if [ ! -d "$myPath" ]; then
        mkdir "$myPath"
    fi
    mount -o loop /root/rpm/EMOS_1.6_x86_64.iso /mnt/EMOS
    cd /mnt
    createrepo .
}

# Create local yum repo
function local_yum(){
    ###### !!!!!!!!!!!!!
    ###### !!!!!!!!!!!!!
    cd /etc/yum.repos.d
    # myPath = "/etc/yum.repos.d/backup"
    if [ ! -d /etc/yum.repos.d/backup/ ]; then
        mkdir /etc/yum.repos.d/backup/
    fi

    mv *.repo ./backup
    touch /etc/yum.repos.d/EMOS.repo
    cat >/etc/yum.repos.d/EMOS.repo<<-EOF
[EMOS]
name=EMOS
baseurl=file:///mnt/
enabled=1
gpgcheck=0
EOF
    yum clean all
    yum list
}

# Install Postfix
function install_postfix(){
    yum -y remove postfix mysql mysql-libs
    yum -y install postfix
    rpm -e sendmail
}

# Configure Postfix
function config_postfix(){
    postconf -n > /etc/postfix/main2.cf
    if [ ! -f /etc/postfix/main.cf.bak ]; then
        mv /etc/postfix/main.cf /etc/postfix/main.cf.bak
    fi
    cp /etc/postfix/main2.cf /etc/postfix/main.cf
    cat >>/etc/postfix/main.cf<<-EOF
# 注意下方的网络号需要改成当前服务器所在的网络号。
mynetworks = 127.0.0.1, ${net_num}/${mask_bit}
# 注意下方的邮箱域名也需要改成相应域名
myhostname = mail.pris.cn
mydestination = \$mynetworks, \$myhostname
# Postfix by zhouhao0925@126.com
mail_name = Postfix - by zhouhao0925@126.com
smtpd_banner = \$myhostname, ESMTP, \$mail_name
# 遇到错误立刻返回
smtpd_error_sleep_time = 0s  
# 邮件大小为5MB，可根据需要修改 
message_size_limit = 5242880
mailbox_size_limit = 5242880
show_user_unknown_table_name = no
# 序列生命周期的设置
bounce_queue_lifetime = 1d
maximal_queue_lifetime = 1d
EOF
    chkconfig postfix on
}

# Install Courier-Authlib
function install_courier_authlib(){
    yum -y install courier-authlib courier-authlib-mysql
    
    if [ ! -f /etc/authlib/authmysqlrc.bak ]; then
        mv /etc/authlib/authmysqlrc /etc/authlib/authmysqlrc.bak
    fi
    cat >/etc/authlib/authmysqlrc<<-EOF
MYSQL_SERVER            localhost
# 如果需要修改原始用户名和密码，请修改下面两项
MYSQL_USERNAME          extmail
MYSQL_PASSWORD          extmail
MYSQL_SOCKET            /var/lib/mysql/mysql.sock
MYSQL_PORT              3306
MYSQL_OPT               0
MYSQL_DATABASE          extmail
MYSQL_USER_TABLE        mailbox
MYSQL_CRYPT_PWFIELD     password
MYSQL_UID_FIELD         uidnumber
MYSQL_GID_FIELD         gidnumber
MYSQL_LOGIN_FIELD       username
MYSQL_HOME_FIELD        homedir
MYSQL_NAME_FIELD        name
MYSQL_MAILDIR_FIELD     maildir
MYSQL_QUOTA_FIELD       quota
MYSQL_SELECT_CLAUSE     SELECT username,password,"",uidnumber,gidnumber,\\
                        CONCAT('/home/domains/',homedir),               \\
                        CONCAT('/home/domains/',maildir),               \\
                        quota,                                          \\
                        name                                            \\
                        FROM mailbox                                    \\
                        WHERE username = '\$(local_part)@\$(domain)'
EOF
    if [ -s /etc/authlib/authdaemonrc ]; then
        sed -ir 's/authmodulelist=".*"/authmodulelist="authmysql"/g' /etc/authlib/authdaemonrc
        sed -ir 's/authmodulelistorig=".*"/authmodulelistorig="authmysql"/g' /etc/authlib/authdaemonrc
    fi
    service courier-authlib start
    chmod 755 /var/spool/authdaemon/
}


# Install 
function install_maildrop(){
    yum -y install maildrop

    cat >>/etc/postfix/master.cf<<-EOF
maildrop   unix        -       n        n        -        -        pipe
  flags=DRhu user=vuser argv=maildrop -w 90 -d \${user}@\${nexthop} \${recipient} \${user} \${extension} {nexthop}
EOF
    cat >>/etc/postfix/main.cf<<-EOF
maildrop_destination_recipient_limit = 1
EOF
}

# Configure Apache
function config_apache(){
    cat >>/etc/httpd/conf/httpd.conf<<-EOF
NameVirtualHost *:80
Include conf/vhost_*.conf
EOF

    cat >>/etc/httpd/conf/vhost_extmail.conf<<-EOF
# VirtualHost for ExtMail Solution
<VirtualHost *:80>
# 请根据自己的服务器设置
ServerName mail.pris.cn
DocumentRoot /var/www/extsuite/extmail/html/
ScriptAlias /extmail/cgi/ /var/www/extsuite/extmail/cgi/
Alias /extmail /var/www/extsuite/extmail/html/
ScriptAlias /extman/cgi/ /var/www/extsuite/extman/cgi/
Alias /extman /var/www/extsuite/extman/html/
# Suexec config（请根据自己的群组和用户设置）
SuexecUserGroup vuser vgroup
</VirtualHost>
EOF

service httpd start
chkconfig httpd on
}

# Uninstall Shadowsocks
function config_extmail(){
    # Install webmail
    yum -y install extsuite-webmail

    cd /var/www/extsuite/extmail
    cp webmail.cf.default webmail.cf
    if [ -s /var/www/extsuite/extmail/webmail.cf ]; then
        sed -ir 's/SYS_MYSQL_USER = .*/SYS_MYSQL_USER = extmail/g' /var/www/extsuite/extmail/webmail.cf
        sed -ir 's/SYS_MYSQL_PASS = .*/SYS_MYSQL_PASS = extmail/g' /var/www/extsuite/extmail/webmail.cf
        sed -ir 's/SYS_MYSQL_DB = .*/SYS_MYSQL_DB = extmail/g' /var/www/extsuite/extmail/webmail.cf
    fi
    chown -R vuser:vgroup /var/www/extsuite/extmail/cgi/

    # Install webman
    yum -y install extsuite-webman
    chown -R vuser:vgroup /var/www/extsuite/extman/cgi/
    if [ ! -d /tmp/extman ]; then
        mkdir /tmp/extman
    fi

    chown -R vuser:vgroup /tmp/extman
}

# Intialize MySQL
function init_mysql(){
    yum -y install mysql*
    service mysqld start
    chkconfig mysqld on

    mysql -u root -p < /var/www/extsuite/extman/docs/extmail.sql
    #######!!!!!!!!! password required
    if [ -s /var/www/extsuite/extman/docs/init.sql ]; then
        sed -ir 's/extmail.org/pris.cn/g' /var/www/extsuite/extman/docs/init.sql
    fi
    mysql -u root -p < /var/www/extsuite/extman/docs/init.sql
    #######!!!!!!!!! password required
    # virtual domain & users
    cp /var/www/extsuite/extman/docs/mysql_virtual_*.cf /etc/postfix/
    cat >>/etc/postfix/main.cf<<-EOF
# extmail配置
virtual_alias_maps = mysql:/etc/postfix/mysql_virtual_alias_maps.cf
virtual_mailbox_domains = mysql:/etc/postfix/mysql_virtual_domains_maps.cf
virtual_mailbox_maps = mysql:/etc/postfix/mysql_virtual_mailbox_maps.cf
virtual_transport = maildrop:
EOF
    service postfix start

    cd /var/www/extsuite/extman/tools
    ./maildirmake.pl /home/domains/pris.cn/postmaster/Maildir
    chown -R vuser:vgroup /home/domains/pris.cn
}

# Install graphic log
function graphic_log(){
    /usr/local/mailgraph_ext/mailgraph-init start
    /var/www/extsuite/extman/daemon/cmdserver -daemon
    echo "/usr/local/mailgraph_ext/mailgraph-init start" >> /etc/rc.d/rc.local
    echo "/var/www/extsuite/extman/daemon/cmdserver -v -d" >> /etc/rc.d/rc.local
}

# Configure Cysus-Sasl
function smtp_setting(){
    yum install cyrus-sasl
    cat >>/etc/postfix/main.cf<<-EOF
# smtpd related config
smtpd_recipient_restrictions =
        permit_mynetworks,
        permit_sasl_authenticated,
        reject_non_fqdn_hostname,
        reject_non_fqdn_sender,
        reject_non_fqdn_recipient,
        reject_unauth_destination,
        reject_unauth_pipelining,
        reject_invalid_hostname,

# SMTP sender login matching config
smtpd_sender_restrictions =
        permit_mynetworks,
        reject_sender_login_mismatch,
        reject_authenticated_sender_login_mismatch,
        reject_unauthenticated_sender_login_mismatch

smtpd_sender_login_maps =
        mysql:/etc/postfix/mysql_virtual_sender_maps.cf,
        mysql:/etc/postfix/mysql_virtual_alias_maps.cf

# SMTP AUTH config here
broken_sasl_auth_clients = yes
smtpd_sasl_auth_enable = yes
smtpd_sasl_local_domain = \$myhostname
smtpd_sasl_security_options = noanonymous
EOF
    mv /usr/lib64/sasl2/smtpd.conf /usr/lib64/sasl2/smtpd.conf.bak
    cat >>/usr/lib64/sasl2/smtpd.conf<<-EOF
pwcheck_method: authdaemond
log_level: 3
mech_list: PLAIN LOGIN
authdaemond_path:/var/spool/authdaemon/socket
EOF
    service postfix restart
    yum -y install telnet
}

# Configure Courier-IMAP
function imap_setting(){
    yum -y install courier-imap
    sed -ir 's/IMAPDSTART=.*/IMAPDSTART=NO/g' /usr/lib/courier-imap/etc/imapd
    sed -ir 's/IMAPDSSLSTART=.*/IMAPDSSLSTART=NO/g' /usr/lib/courier-imap/etc/imapd-ssl
    service courier-imap restart
}

function off_iptables(){
    service iptables stop
    chkconfig iptables off
}

function stat_update(){
    service courier-authlib restart
    service httpd restart
    service mysqld restart
    service postfix restart
    /usr/local/mailgraph_ext/mailgraph-init restart
    service courier-imap restart
    service iptables stop
    mv /etc/yum/repos.d/backup/*.repo /etc/yum/repos.d/
}
# Initialization step
# action=$1
# [  -z $1 ] && action=install
# case "$action" in
# install)
#     install_shadowsocks
#     ;;
# uninstall)
#     uninstall_shadowsocks
#     ;;
# *)
#     echo "Arguments error! [${action} ]"
#     echo "Usage: `basename $0` {install|uninstall}"
#     ;;
# esac
install_postfix_extmail