#
# Cookbook:: chef_automate_wrapper
# Recipe:: default
#
# Copyright:: 2019, The Authors, All Rights Reserved.

remote_file '/bin/jq' do
  source node['chef_automate_wrapper']['jq_url']
  mode '0755'
end

config = node['chef_automate_wrapper']['config']

hostname = if node['chef_automate_wrapper']['fqdn'] != ''
             node['chef_automate_wrapper']['fqdn']
           elsif node['cloud']
             node['cloud']['public_ipv4_addrs'].first
           end

config += if node['chef_automate_wrapper']['dc_token'] != ''
            <<~EOF
             [auth_n.v1.sys.service]
             a1_data_collector_token = "#{node['chef_automate_wrapper']['dc_token']}"

            EOF
          else
            ''
          end

config += if node['chef_automate_wrapper']['cert'] != '' &&
             node['chef_automate_wrapper']['cert_key'] != ''
            <<~EOF
              [[load_balancer.v1.sys.frontend_tls]]
              cert = """#{node['chef_automate_wrapper']['cert']}"""
              key = """#{node['chef_automate_wrapper']['cert_key']}"""
            EOF
          else
            ''
          end

config += <<~EOF
    [global.v1]
    fqdn = "#{hostname}"

EOF

chef_automatev2 'chef-automate' do
  channel node['chef_automate_wrapper']['channel'].to_sym
  version node['chef_automate_wrapper']['version']
  config (node['platform_family'] == 'suse' ||  node['platform'] == 'ubuntu') ? '' : config
  accept_license node['chef_automate_wrapper']['accept_license'].to_s == 'true'
end

execute 'apply_license' do
  command "chef-automate license apply #{node['chef_automate_wrapper']['license']}"
  only_if { node['chef_automate_wrapper']['license'] != '' }
  not_if 'chef-automate license status | grep Expiration'
end

execute 'update_admin_password' do
  command "chef-automate iam admin-access restore #{node['chef_automate_wrapper']['admin_password']}"
  not_if { node['chef_automate_wrapper']['admin_password'] == '' }
end

# suse is different
if node['platform_family'] == 'suse' || node['platform'] == 'ubuntu'

  link '/usr/bin/chef-automate' do
    to '/bin/chef-automate'
    only_if { ::File.file?('/bin/chef-automate') }
  end

  chef_automatev2 'chef-automate' do
    action :reconfigure
    channel node['chef_automate_wrapper']['channel'].to_sym
    version node['chef_automate_wrapper']['version']
    config config
    accept_license node['chef_automate_wrapper']['accept_license'].to_s == 'true'
  end

end

ruby_block 'parse_creds' do
  block do
    require 'json'
    require 'tomlrb'
    src  = Tomlrb.load_file(
      "#{Chef::Config[:file_cache_path]}/automate-credentials.toml")
    dest = node['chef_automate_wrapper']['creds_json_path']
    pass = node['chef_automate_wrapper']['admin_password']
    tkn = node['chef_automate_wrapper']['dc_token']
    src['url'] = "https://#{hostname}" if hostname != ''
    src['password'] = pass if pass != ''
    src['token'] = tkn
    ::File.write(dest, src.to_json) unless ::File.exist?(dest)
  end
end

file node['chef_automate_wrapper']['data_script'] do
  content <<~EOF
    #!/bin/bash
    cat #{node['chef_automate_wrapper']['creds_json_path']} | /bin/jq -r '.'
  EOF
  mode '0755'
end
