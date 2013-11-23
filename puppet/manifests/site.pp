# test
#
# one machine setup with weblogic 12.1.2
# creates an WLS Domain with JAX-WS (advanced, soap over jms)
# needs jdk7, orawls, orautils, fiddyspence-sysctl, erwbgy-limits puppet modules
#

node 'admin.example.com' {

  
  include os, ssh, java, orawls::weblogic, orautils
  include bsu, domains, nodemanager, startwls, userconfig
  include machines, managed_servers
  include clusters
  include jms_servers,jms_modules,jms_module_subdeployments
  include jms_module_quotas,jms_module_cfs,jms_module_objects_errors,jms_module_objects
  include pack_domain

  Class['java'] -> Class['orawls::weblogic']
}



# operating settings for Middleware
class os {

  notice "class os ${operatingsystem}"

  host{"node1":
    ip => "10.10.10.100",
    host_aliases => ['node1.infoplus.nl','node1'],
  }

  host{"node2":
    ip => "10.10.10.200",
    host_aliases => ['node2.infoplus.nl','node2'],
  }

  exec { "create swap file":
    command => "/bin/dd if=/dev/zero of=/var/swap.1 bs=1M count=8192",
    creates => "/var/swap.1",
  }

  exec { "attach swap file":
    command => "/sbin/mkswap /var/swap.1 && /sbin/swapon /var/swap.1",
    require => Exec["create swap file"],
    unless => "/sbin/swapon -s | grep /var/swap.1",
  }

  #add swap file entry to fstab
  exec {"add swapfile entry to fstab":
    command => "/bin/echo >>/etc/fstab /var/swap.1 swap swap defaults 0 0",
    require => Exec["attach swap file"],
    user => root,
    unless => "/bin/grep '^/var/swap.1' /etc/fstab 2>/dev/null",
  }

  service { iptables:
        enable    => false,
        ensure    => false,
        hasstatus => true,
  }

  group { 'dba' :
    ensure => present,
  }

  # http://raftaman.net/?p=1311 for generating password
  user { 'oracle' :
    ensure     => present,
    groups     => 'dba',
    shell      => '/bin/bash',
    password   => '$1$DSJ51vh6$4XzzwyIOk6Bi/54kglGk3.',
    home       => "/home/oracle",
    comment    => 'Oracle user created by Puppet',
    managehome => true,
    require    => Group['dba'],
  }

  $install = [ 'binutils.x86_64','unzip.x86_64']


  package { $install:
    ensure  => present,
  }

  class { 'limits':
    config => {
               '*'       => {  'nofile'  => { soft => '2048'   , hard => '8192',   },},
               'oracle'  => {  'nofile'  => { soft => '65536'  , hard => '65536',  },
                               'nproc'   => { soft => '2048'   , hard => '16384',   },
                               'memlock' => { soft => '1048576', hard => '1048576',},
                               'stack'   => { soft => '10240'  ,},},
               },
    use_hiera => false,
  }

  sysctl { 'kernel.msgmnb':                 ensure => 'present', permanent => 'yes', value => '65536',}
  sysctl { 'kernel.msgmax':                 ensure => 'present', permanent => 'yes', value => '65536',}
  sysctl { 'kernel.shmmax':                 ensure => 'present', permanent => 'yes', value => '2588483584',}
  sysctl { 'kernel.shmall':                 ensure => 'present', permanent => 'yes', value => '2097152',}
  sysctl { 'fs.file-max':                   ensure => 'present', permanent => 'yes', value => '6815744',}
  sysctl { 'net.ipv4.tcp_keepalive_time':   ensure => 'present', permanent => 'yes', value => '1800',}
  sysctl { 'net.ipv4.tcp_keepalive_intvl':  ensure => 'present', permanent => 'yes', value => '30',}
  sysctl { 'net.ipv4.tcp_keepalive_probes': ensure => 'present', permanent => 'yes', value => '5',}
  sysctl { 'net.ipv4.tcp_fin_timeout':      ensure => 'present', permanent => 'yes', value => '30',}
  sysctl { 'kernel.shmmni':                 ensure => 'present', permanent => 'yes', value => '4096', }
  sysctl { 'fs.aio-max-nr':                 ensure => 'present', permanent => 'yes', value => '1048576',}
  sysctl { 'kernel.sem':                    ensure => 'present', permanent => 'yes', value => '250 32000 100 128',}
  sysctl { 'net.ipv4.ip_local_port_range':  ensure => 'present', permanent => 'yes', value => '9000 65500',}
  sysctl { 'net.core.rmem_default':         ensure => 'present', permanent => 'yes', value => '262144',}
  sysctl { 'net.core.rmem_max':             ensure => 'present', permanent => 'yes', value => '4194304', }
  sysctl { 'net.core.wmem_default':         ensure => 'present', permanent => 'yes', value => '262144',}
  sysctl { 'net.core.wmem_max':             ensure => 'present', permanent => 'yes', value => '1048576',}

}

class ssh {
  require os

  notice 'class ssh'

  file { "/home/oracle/.ssh/":
    owner  => "oracle",
    group  => "dba",
    mode   => "700",
    ensure => "directory",
    alias  => "oracle-ssh-dir",
  }
  
  file { "/home/oracle/.ssh/id_rsa.pub":
    ensure  => present,
    owner   => "oracle",
    group   => "dba",
    mode    => "644",
    source  => "/vagrant/ssh/id_rsa.pub",
    require => File["oracle-ssh-dir"],
  }
  
  file { "/home/oracle/.ssh/id_rsa":
    ensure  => present,
    owner   => "oracle",
    group   => "dba",
    mode    => "600",
    source  => "/vagrant/ssh/id_rsa",
    require => File["oracle-ssh-dir"],
  }
  
  file { "/home/oracle/.ssh/authorized_keys":
    ensure  => present,
    owner   => "oracle",
    group   => "dba",
    mode    => "644",
    source  => "/vagrant/ssh/id_rsa.pub",
    require => File["oracle-ssh-dir"],
  }        
}

class java {
  require os

  notice 'class java'

  $remove = [ "java-1.7.0-openjdk.x86_64", "java-1.6.0-openjdk.x86_64" ]

  package { $remove:
    ensure  => absent,
  }

  include jdk7

  jdk7::install7{ 'jdk1.7.0_45':
      version              => "7u45" , 
      fullVersion          => "jdk1.7.0_45",
      alternativesPriority => 18000, 
      x64                  => true,
      downloadDir          => "/data/install",
      urandomJavaFix       => true,
      sourcePath           => "/vagrant",
  }

}


class bsu{
  require orawls::weblogic

  notice 'class bsu'
  $default_params = {}
  $bsu_instances = hiera('bsu_instances', [])
  create_resources('orawls::bsu',$bsu_instances, $default_params)
}

class domains{
  require orawls::weblogic, bsu

  notice 'class domains'
  $default_params = {}
  $domain_instances = hiera('domain_instances', [])
  create_resources('orawls::domain',$domain_instances, $default_params)
}

class nodemanager {
  require orawls::weblogic, domains

  notify { 'class nodemanager':} 
  $default_params = {}
  $nodemanager_instances = hiera('nodemanager_instances', [])
  create_resources('orawls::nodemanager',$nodemanager_instances, $default_params)
}

class startwls {
  require orawls::weblogic, domains,nodemanager


  notify { 'class startwls':} 
  $default_params = {}
  $control_instances = hiera('control_instances', [])
  create_resources('orawls::control',$control_instances, $default_params)
}

class userconfig{
  require orawls::weblogic, domains, nodemanager, startwls 

  notify { 'class userconfig':} 
  $default_params = {}
  $userconfig_instances = hiera('userconfig_instances', [])
  create_resources('orawls::storeuserconfig',$userconfig_instances, $default_params)
} 

class machines{
  require userconfig

  notify { 'class machines':} 
  $default_params = {}
  $machines_instances = hiera('machines_instances', [])
  create_resources('orawls::wlstexec',$machines_instances, $default_params)
}

class managed_servers{
  require machines

  notify { 'class managed_servers':} 

  # lookup all managed_servers_instances in all hiera files
  $allHieraEntries = hiera_array('managed_servers_instances')


  $allHieraEntries.each |$hieraEntry| { 
      $hieraEntry.each |$hieraTitle,$hieraEntryValues| {
        notice "$hieraTitle"

        $default_params = $hieraEntryValues.select |$x| {  $x[0] == 'global_parameters'  }
        $entries        = $hieraEntryValues.reject |$x| {  $x[0] == 'global_parameters'  }
        create_resources('orawls::wlstexec',
                          $entries, 
                          $default_params['global_parameters'])
     }
  } 

}

class clusters{
  require managed_servers

  notify { 'class clusters':} 

  # lookup all managed_servers_instances in all hiera files
  $allHieraEntries = hiera_array('cluster_instances')
  $allHieraEntries.each |$index,$hieraEntry| { 
      $hieraEntry.each |$hieraTitle,$hieraEntryValues| {
        $default_params = $hieraEntryValues.select |$x| {  $x[0] == 'global_parameters'  }
        $entries = $hieraEntryValues.reject |$x| {  $x[0] == 'global_parameters'  }
        create_resources('orawls::wlstexec',$entries, $default_params['global_parameters'])
     }
  } 
}


class jms_servers{
  require clusters

  notify { 'class jms_servers':} 
  # lookup all managed_servers_instances in all hiera files
  $allHieraEntries = hiera_array('jms_servers_instances')
  $allHieraEntries.each |$index,$hieraEntry| { 
      $hieraEntry.each |$hieraTitle,$hieraEntryValues| {
        $default_params = $hieraEntryValues.select |$x| {  $x[0] == 'global_parameters'  }
        $entries = $hieraEntryValues.reject |$x| {  $x[0] == 'global_parameters'  }
        create_resources('orawls::wlstexec',$entries, $default_params['global_parameters'])
     }
  } 


}

class jms_modules{
  require jms_servers

  notify { 'class jms_modules':} 

  # lookup all managed_servers_instances in all hiera files
  $allHieraEntries = hiera_array('jms_module_instances')
  $allHieraEntries.each |$index,$hieraEntry| { 
      $hieraEntry.each |$hieraTitle,$hieraEntryValues| {
        $default_params = $hieraEntryValues.select |$x| {  $x[0] == 'global_parameters'  }
        $entries = $hieraEntryValues.reject |$x| {  $x[0] == 'global_parameters'  }
        create_resources('orawls::wlstexec',$entries, $default_params['global_parameters'])
     }
  } 


}

class jms_module_subdeployments{
  require jms_modules

  notify { 'class jms_module_subdeployments':} 
  # lookup all managed_servers_instances in all hiera files
  $allHieraEntries = hiera_array('jms_module_subdeployments_instances')
  $allHieraEntries.each |$index,$hieraEntry| { 
      $hieraEntry.each |$hieraTitle,$hieraEntryValues| {
        $default_params = $hieraEntryValues.select |$x| {  $x[0] == 'global_parameters'  }
        $entries = $hieraEntryValues.reject |$x| {  $x[0] == 'global_parameters'  }
        create_resources('orawls::wlstexec',$entries, $default_params['global_parameters'])
     }
  } 

}
class jms_module_quotas{
  require jms_module_subdeployments

  notify { 'class jms_module_quotas':} 
  # lookup all managed_servers_instances in all hiera files
  $allHieraEntries = hiera_array('jms_module_quotas_instances')
  $allHieraEntries.each |$index,$hieraEntry| { 
      $hieraEntry.each |$hieraTitle,$hieraEntryValues| {
        $default_params = $hieraEntryValues.select |$x| {  $x[0] == 'global_parameters'  }
        $entries = $hieraEntryValues.reject |$x| {  $x[0] == 'global_parameters'  }
        create_resources('orawls::wlstexec',$entries, $default_params['global_parameters'])
     }
  } 


}

class jms_module_cfs{
  require jms_module_quotas

  notify { 'class jms_module_cfs':} 
  # lookup all managed_servers_instances in all hiera files
  $allHieraEntries = hiera_array('jms_module_cf_instances')
  $allHieraEntries.each |$index,$hieraEntry| { 
      $hieraEntry.each |$hieraTitle,$hieraEntryValues| {
        $default_params = $hieraEntryValues.select |$x| {  $x[0] == 'global_parameters'  }
        $entries = $hieraEntryValues.reject |$x| {  $x[0] == 'global_parameters'  }
        create_resources('orawls::wlstexec',$entries, $default_params['global_parameters'])
     }
  } 


}

class jms_module_objects_errors{
  require jms_module_cfs

  notify { 'class jms_module_objects_errors':} 
  # lookup all managed_servers_instances in all hiera files
  $allHieraEntries = hiera_array('jms_module_jms_errors_instances')
  $allHieraEntries.each |$index,$hieraEntry| { 
      $hieraEntry.each |$hieraTitle,$hieraEntryValues| {
        $default_params = $hieraEntryValues.select |$x| {  $x[0] == 'global_parameters'  }
        $entries = $hieraEntryValues.reject |$x| {  $x[0] == 'global_parameters'  }
        create_resources('orawls::wlstexec',$entries, $default_params['global_parameters'])
     }
  } 

}


class jms_module_objects{
  require jms_module_objects_errors

  notify { 'class jms_module_objects':} 

  $var = 
    [{  'ClusterOne' => {
            'global_parameters' => 
               {
                log_output     => true,
                weblogic_type  => "jmsobject",
                script         => 'createJmsQueueOrTopic.py',
                params         => 
                  [  "subDeploymentName = 'jmsServers'",
                     "jmsModuleName     = 'jmsClusterModule'",
                     "distributed       = 'true'",
                     "balancingPolicy   = 'Round-Robin'",
                     "useRedirect       = 'true'",
                     "limit             = '3'",
                     "policy            = 'Redirect'",
                     "errorObject       = 'ErrorQueue'",
                  ],
              } ,
            'createJmsQueueforJmsModule1' => 
               {
                 weblogic_object_name  => "Queue1",
                 params                => 
                   [ "jmsType           = 'queue'",
                     "jmsName           = 'Queue1'",
                     "jmsJNDIName       = 'jms/Queue1'",
                   ],
               } ,
             'createJmsQueueforJmsModule2' => 
               {
                 weblogic_object_name  => "Queue2",
                 params                => 
                   [ "jmsType           = 'queue'",
                     "jmsName           = 'Queue2'",
                     "jmsJNDIName       = 'jms/Queue2'",
                   ],
              },
        },       
    },
   ] 

  # lookup all jms_instances in all hiera files
  $allHieraEntries = hiera_array('jms_module_jms_instances')

  $allHieraEntries.each |$hieraEntry| {  
      # every hiera entry
      $hieraEntry.each |$hieraTitle,$hieraEntryValues| {
        notice "$hieraTitle"
        # select global params of the hiera entry
        $globals        = $hieraEntryValues.select |$x| {  $x[0] == 'global_parameters'  }
        # only select params from global params, will merge later
        $params         = $globals['global_parameters'].select |$x| {  $x[0] == 'params'  }
        # remove params from global params, so we will get all the default params
        $default_params = $globals['global_parameters'].reject |$x| {  $x[0] == 'params'  }
        # get all entries except global params
        $wlstEntries = $hieraEntryValues.reject |$x| {  $x[0] == 'global_parameters'  }
        # for every create WLST object
        $wlstEntries.each |$index5,$value5 | { 
           $entry_other_params = $value5.reject |$x| {  $x[0] == 'params'  }
           $entry_params = $value5['params']

           # merge WLST params with global params
           $all_params = $params['params'] + $entry_params
           # create new hash 
           $createEntry = {  "$index5" => 
                                 {
                                    weblogic_object_name  => $entry_other_params['weblogic_object_name'],
                                    params                => $all_params ,
                                 }
                          }
           # create WLST object , add entry plus default               
           create_resources('orawls::wlstexec',$createEntry, $default_params)               
        }
     }
  } 

}

class pack_domain{
  require jms_module_objects

  notify { 'class pack_domain':} 
  $default_params = {}
  $pack_domain_instances = hiera('pack_domain_instances', [])
  create_resources('orawls::packdomain',$pack_domain_instances, $default_params)
}