# Detect if we're running on macOS or Linux
OS_TYPE=$(uname -s)

# For macOS, use netstat to find the active interface
if [[ "$OS_TYPE" == "Darwin" ]]; then
    IP=$(ipconfig getifaddr en0)
else
    # For Linux, use ip route to find the active interface
    # TODO Test on Linux
    INTERFACE=$(ip route | grep default | awk '{print $5}')
    IP=$(ip addr show $INTERFACE | grep inet | awk '{print $2}' | cut -d/ -f1)
fi

# Get the IP address of the default network interface
echo "Setting LB IP to $IP"

# Apply MetalLB configuration with the dynamic IP
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: local-ip-pool
  namespace: metallb-system
spec:
  addresses:
    - $IP/32

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
EOF