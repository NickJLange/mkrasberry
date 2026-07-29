## 1. Network Research

- [x] 1.1 Identify network equipment (switches/routers) between DNS servers
- [ ] 1.2 Verify Ubiquity switch allows VRRP multicast (224.0.0.18)
- [ ] 1.3 Verify commodity switches allow VRRP
- [ ] 1.4 Check firewall rules between DNS server pairs

## 2. Address Planning

- [x] 2.1 Choose VIP for Wisconsin - 192.168.20.2
- [x] 2.2 Choose VIP for New York - 192.168.100.2
- [x] 2.3 Choose VIP for Miyagi - 192.168.3.2
- [ ] 2.4 Verify VIPs are unused in each subnet

## 3. Implementation Design

- [ ] 3.1 Design keepalived configuration for each pair
- [ ] 3.2 Plan firewall rules for VRRP protocol (protocol 112)
- [ ] 3.3 Design monitoring for keepalived state
- [ ] 3.4 Plan DHCP changes (reserve .2 for VIP, shift range to .11-.254)

## 4. Risk Analysis

- [x] 4.1 Document ARP cache behavior after failover
- [x] 4.2 Document split-brain prevention
- [x] 4.3 Document failover timing expectations
- [ ] 4.4 Plan testing strategy

## 5. Decision Documentation

- [x] 5.1 Decide on HA approach - keepalived/VRRP
- [ ] 5.2 Decide on preemption policy (immediate vs delayed)
- [x] 5.3 Decide on cross-region fallback - NO
- [x] 5.4 Document final recommendations
