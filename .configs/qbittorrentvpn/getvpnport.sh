#!/bin/bash
# ==============================================================================
# Script Name: getvpnport.sh (.configs/qbittorrentvpn/getvpnport.sh)
# Description:
#   Custom Private Internet Access (PIA) NextGen dynamic port-forwarding helper
#   script bind-mounted into the 'qbittorrentvpn' container at '/root/getvpnport.sh'
#   from '/volume1/docker/qbittorrentvpn/data/getvpnport.sh'.
#
# Purpose and Why This Override Exists:
#   In 'binhex/arch-qbittorrentvpn:4.3.3-1-02', the bundled '/root/getvpnport.sh'
#   had a routing/interface binding defect when requesting the PIA NextGen token
#   on certain LAN topologies (attempting to reach 10.0.0.1 or routing token
#   requests outside the VPN interface).
#
#   This override explicitly binds the token generation request to the active
#   VPN tunnel interface ('--interface "${VPN_DEVICE_TYPE}"' / 'tun0') and
#   implements PIA's 4-stage NextGen port-forwarding protocol:
#     1. port_forward_status():
#        Queries PIA's public server list API to verify whether the configured
#        OpenVPN remote endpoint (${VPN_REMOTE_SERVER}) supports port forwarding.
#     2. get_incoming_port_nextgen():
#        - Sources '/root/getvpnip.sh' to obtain '${vpn_gateway_ip}' on tun0.
#        - Authenticates with ${VPN_USER}:${VPN_PASS} over ${VPN_DEVICE_TYPE}
#          against 'https://www.privateinternetaccess.com/gtoken/generateToken'
#          to obtain a 24-hour PIA token.
#        - Queries 'https://${vpn_gateway_ip}:19999/getSignature?token=...' over
#          the VPN tunnel to obtain a base64-encoded JSON payload (containing
#          the assigned TCP/UDP port and ~60-day expiration timestamp) and
#          cryptographic signature.
#        - Writes the assigned decimal port number to '/tmp/getvpnport', which
#          binhex's '/home/nobody/qbittorrent.sh' script reads to configure
#          qBittorrent's listening port automatically.
#     3. bind_incoming_port_nextgen():
#        Runs in the background and calls 'https://${vpn_gateway_ip}:19999/bindPort'
#        every 15 minutes ('sleep 15m') with the payload and signature to keep
#        the forwarded port lease alive on PIA's gateway.
#     4. trigger_failure() & set_trap():
#        Touches '/tmp/portfailure' if token acquisition or port binding fails
#        after 12 retries so the container's watchdog can re-initialize the
#        tunnel, and traps INT/TERM/EXIT to clean up background sleep jobs.
# ==============================================================================

# ------------------------------------------------------------------------------
# Function: port_forward_status
# Description:
#   Queries PIA's v4 server list API ('https://serverlist.piaservers.net/vpninfo/servers/v4')
#   and checks whether the currently selected OpenVPN endpoint (${VPN_REMOTE_SERVER})
#   has 'port_forward == true'. Logs a warning and prints the list of supported
#   endpoints if the current server does not support port forwarding.
# Globals Read:
#   VPN_REMOTE_SERVER, pia_vpninfo_api, jq_query_portforward_enabled
# ------------------------------------------------------------------------------
function port_forward_status() {

	echo "[info] Port forwarding is enabled"

	echo "[info] Checking endpoint '${VPN_REMOTE_SERVER}' is port forward enabled..."

	# Fetch the PIA server list JSON (ignoring TLS cert verification inside the container)
	jq_query_result=$(curl --silent --insecure "${pia_vpninfo_api}")

	if [[ "${?}" != 0 ]]; then

		echo "[warn] PIA VPN info API currently down, skipping endpoint port forward check"

	else

		# Extract DNS hostnames of all PIA regions where port_forward == true
		# and flatten into a single space-delimited line via xargs.
		jq_query_details=$(echo "${jq_query_result}" | jq -r "${jq_query_portforward_enabled}" 2> /dev/null | xargs)

		# Check whether VPN_REMOTE_SERVER appears as a whole word (-w) in the supported list.
		echo "${jq_query_details}" | grep -qw "${VPN_REMOTE_SERVER}"

		if [[ "${?}" != 0 ]]; then

			echo "[warn] PIA endpoint '${VPN_REMOTE_SERVER}' is not in the list of endpoints that support port forwarding, DL/UL speeds maybe slow"
			echo "[info] Please consider switching to one of the endpoints shown below"

		else

			echo "[info] PIA endpoint '${VPN_REMOTE_SERVER}' is in the list of endpoints that support port forwarding"

		fi

		# Convert space-separated string into a bash array for formatted logging
		IFS=' ' read -ra jq_query_details_list <<< "${jq_query_details}"

		echo "[info] List of PIA endpoints that support port forwarding:-"

		for i in "${jq_query_details_list[@]}"; do
				echo "[info] ${i}"
		done

	fi

}

# ------------------------------------------------------------------------------
# Function: get_incoming_port_nextgen
# Description:
#   Acquires a PIA NextGen port-forwarding token and signed port payload over
#   the active VPN tunnel, writes the allocated port number to '/tmp/getvpnport',
#   starts the 15-minute background keepalive loop ('bind_incoming_port_nextgen'),
#   and sleeps until 2 hours before the ~60-day port lease expires before
#   requesting a fresh port allocation.
# Globals Read:
#   VPN_DEVICE_TYPE, VPN_USER, VPN_PASS, DEBUG
# Globals Mutated:
#   vpn_gateway_ip (sourced from /root/getvpnip.sh), payload, signature, port
# Side Effects:
#   Writes allocated port number to '/tmp/getvpnport' and spawns
#   'bind_incoming_port_nextgen' in the background.
# ------------------------------------------------------------------------------
function get_incoming_port_nextgen() {

	retry_count=12
	retry_wait_secs=10

	while true; do

		# Populate ${vpn_gateway_ip} from binhex's helper script once tun0 is up
		source /root/getvpnip.sh

		# Stage 1: Authenticate with PIA over the VPN interface (${VPN_DEVICE_TYPE}, e.g. tun0)
		# to obtain a short-lived authentication token.
		while true; do

			if [ "${retry_count}" -eq "0" ]; then

				echo "[warn] Unable to download PIA json to generate token, exiting script..."
				trigger_failure ; return 1

			fi

			# Binding curl to --interface "${VPN_DEVICE_TYPE}" ensures the token request
			# traverses the VPN tunnel rather than conflicting with local LAN routes.
			token_json_response=$(curl --interface "${VPN_DEVICE_TYPE}" --silent --insecure -u "${VPN_USER}:${VPN_PASS}" "https://www.privateinternetaccess.com/gtoken/generateToken")

			if [ "$(echo "${token_json_response}" | jq -r '.status')" != "OK" ]; then

				echo "[warn] Unable to successfully download PIA json to generate token from URL https://www.privateinternetaccess.com/gtoken/generateToken"
				echo "[info] ${retry_count} retries left"
				echo "[info] Retrying in ${retry_wait_secs} secs..."
				retry_count=$((retry_count-1))
				sleep "${retry_wait_secs}"s & wait $!

			else

				retry_count=12
				break

			fi

		done

		# Stage 2: Exchange the token with the VPN gateway's port-forwarding API
		# (https://${vpn_gateway_ip}:19999/getSignature) to obtain a signed port lease.
		while true; do

			if [ "${retry_count}" -eq "0" ]; then

				echo "[warn] Unable to download PIA json payload, exiting script..."
				trigger_failure ; return 1

			fi

			token=$(echo "${token_json_response}" | jq -r '.token')

			# URL-encode the token parameter so base64 characters (+, /, =) are not corrupted
			payload_and_sig=$(curl --insecure --silent --max-time 5 --get --data-urlencode "token=${token}" "https://${vpn_gateway_ip}:19999/getSignature")

			if [ "$(echo "${payload_and_sig}" | jq -r '.status')" != "OK" ]; then

				echo "[warn] Unable to successfully download PIA json payload from URL 'https://${vpn_gateway_ip}:19999/getSignature' using token '${token}'"
				echo "[info] ${retry_count} retries left"
				echo "[info] Retrying in ${retry_wait_secs} secs..."
				retry_count=$((retry_count-1))
				sleep "${retry_wait_secs}"s & wait $!

			else

				retry_count=12
				break

			fi

		done

		payload=$(echo "${payload_and_sig}" | jq -r '.payload')
		signature=$(echo "${payload_and_sig}" | jq -r '.signature')

		# Base64-decode the payload JSON to extract the assigned port and expiration date
		payload_decoded=$(echo "${payload}" | base64 -d | jq)

		if [ "${?}" -eq 0 ]; then

			token=$(echo "${payload_decoded}" | jq -r '.token')
			port=$(echo "${payload_decoded}" | jq -r '.port')
			# expires_at is an ISO-8601 UTC timestamp (~2 months in the future)
			expires_at=$(echo "${payload_decoded}" | jq -r '.expires_at')

			if [[ "${DEBUG}" == "true" ]]; then

				echo "[debug] Token is '${token}'"
				echo "[debug] Port allocated is '${port}'"
				echo "[debug] Port expires at '${expires_at}'"

			fi

		else

			echo "[warn] Unable to decode payload, exiting script..."
			trigger_failure ; return 1

		fi

		if [[ "${port}" =~ ^-?[0-9]+$ ]]; then

			# Write the assigned port to /tmp/getvpnport so binhex's qbittorrent.sh
			# reads it and updates qBittorrent's incoming peer port.
			echo "${port}" > /tmp/getvpnport

		else

			echo "[warn] Incoming port assigned is not a decimal value '${port}', exiting script..."
			trigger_failure ; return 1

		fi

		# Launch the 15-minute port-binding keepalive loop in the background
		bind_incoming_port_nextgen &

		# Sleep until 2 hours before the ~60-day payload lease expires, then loop
		# to acquire a new token and port payload.
		current_datetime_epoch=$(TZ=GMT date -d '2 hour ago' +%s)
		expires_at_convert_epoch=$(date -d "${expires_at}" +%s)
		expires_at_delta=$(( (expires_at_convert_epoch - current_datetime_epoch) ))

		sleep "${expires_at_delta}"s & wait $!

	done

}

# ------------------------------------------------------------------------------
# Function: bind_incoming_port_nextgen
# Description:
#   Background keepalive loop that calls 'https://${vpn_gateway_ip}:19999/bindPort'
#   every 15 minutes with the base64 payload and cryptographic signature.
#   PIA closes the forwarded port if '/bindPort' is not called at least once
#   every 15 minutes.
# Globals Read:
#   vpn_gateway_ip, payload, signature, port
# ------------------------------------------------------------------------------
function bind_incoming_port_nextgen() {

	# Install signal trap in the background subshell so it exits cleanly on container stop
	set_trap

	retry_count=12
	retry_wait_secs=10

	while true; do

		if [ "${retry_count}" -eq "0" ]; then

			echo "[warn] Unable to bind incoming port '${port}', exiting script..."
			trigger_failure ; return 1

		fi

		bind_port=$(curl --insecure --silent --max-time 5 --get --data-urlencode "payload=${payload}" --data-urlencode "signature=${signature}" "https://${vpn_gateway_ip}:19999/bindPort")

		if [ "$(echo "${bind_port}" | jq -r '.status')" != "OK" ]; then

			echo "[warn] Unable to bind port using URL 'https://${vpn_gateway_ip}:19999/bindPort'"
			retry_count=$((retry_count-1))
			echo "[info] ${retry_count} retries left"
			echo "[info] Retrying in ${retry_wait_secs} secs..."
			sleep "${retry_wait_secs}"s & wait $!
			continue

		else

			retry_count=12

		fi

		echo "[info] Successfully assigned and bound incoming port '${port}'"

		# PIA requires re-binding the port every 15 minutes to keep the forward active
		sleep 15m & wait $!

	done

}

# ------------------------------------------------------------------------------
# Function: trigger_failure
# Description:
#   Signals a port-forwarding failure to the container's supervisory scripts by
#   creating '/tmp/portfailure'.
# ------------------------------------------------------------------------------
function trigger_failure() {

	echo "[info] Port forwarding failure, creating file '/tmp/portfailure' to indicate failure..."
	touch "/tmp/portfailure"
	chmod +r "/tmp/portfailure"

}

# ------------------------------------------------------------------------------
# Function: set_trap
# Description:
#   Registers a trap for SIGINT, SIGTERM, and EXIT to terminate any backgrounded
#   child processes (such as 'sleep ... & wait $!' or 'bind_incoming_port_nextgen &')
#   when the script or OpenVPN tunnel is restarted.
# ------------------------------------------------------------------------------
function set_trap() {

	trap 'kill $(jobs -p); break; exit 1' INT TERM EXIT

}

# ==============================================================================
# Main Execution Entrypoint
# ==============================================================================
# Run only for torrent applications (not sabnzbd/privoxy) when VPN_PROV == "pia"
if [[ "${APPLICATION}" != "sabnzbd" ]] && [[ "${APPLICATION}" != "privoxy" ]] && [[ "${VPN_PROV}" == "pia" ]]; then

	if [[ "${STRICT_PORT_FORWARD}" == "no" ]]; then

		echo "[info] Port forwarding is not enabled"
		touch /tmp/getvpnport

	else

		echo "[info] Script started to assign incoming port"

		# Record PID so OpenVPN restart scripts can terminate this process cleanly
		echo "${BASHPID}" > '/tmp/getvpnport.pid'

		set_trap

		pia_vpninfo_api="https://serverlist.piaservers.net/vpninfo/servers/v4"
		jq_query_portforward_enabled='.regions | .[] | select(.port_forward=='true') | .dns'
		jq_query_metadata_ip=".regions | .[] | select(.dns | match(\"^${VPN_REMOTE_SERVER}\")) | .servers | .meta | .[] | .ip"

		port_forward_status
		get_incoming_port_nextgen

		echo "[info] Script finished to assign incoming port"

	fi

else

	echo "[info] Application does not require port forwarding or VPN provider is != pia, skipping incoming port assignment"

fi
