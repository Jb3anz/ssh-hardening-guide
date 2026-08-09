# SSH hardening guide

A technical guide that shows how to secure a Linux VPS, ensuring strict SSH endpoint isolation and disabling root vulnerabilities and enable automated firewall protections

---
## 🚀 Quickstart (using the script)
 
If you'd rather not run every command by hand, this repo includes `ssh-hardening-setup.sh`, an interactive script that automates everything covered below, user creation, key deployment, sshd hardening, UFW, and fail2ban.
 
**Before you start:** generate your SSH keypair locally first (see Step 1 below), you'll need the contents of your `.pub` file ready to paste in during the script.
 
```bash
git clone https://github.com/jb3anz/ssh-hardening-guide.git
cd ssh-hardening-guide
chmod +x script.sh
sudo ./script.sh
```
 
That runs **Phase 1**: it checks whether `sshd` is installed, creates a non-root sudo user, and deploys your public key with the correct permissions. When it finishes, it will tell you to stop.
 
> [!WARNING]
> Do not close your current session. Open a **brand new** terminal and confirm you can log in as the new user with your key, no password prompt. If SSH asks you for a `password:` at any point, your key isn't working yet, go fix that before continuing (see the Troubleshooting section below).
 
Once you've confirmed the new login works, run Phase 2:
 
```bash
sudo ./ssh-hardening-setup.sh --phase2
```
 
This backs up `sshd_config`, disables password/root SSH login, validates the config before reloading, and walks you through optional UFW and fail2ban setup.
 
The rest of this README explains what each step does manually and why, useful if you want to understand or customize the process rather than just run the script.
 
---
## 🚀 Step 1: Generate your local SSH key

Using a Password isnt secure enough as it is possible to brute force and guess the password instead we will use the **Ed25519 Curve** which offers better cyrptographic strength and offers more performance than legacy RSA keys

On your local (Actual) linux PC :

```bash
ssh-keygen -t ed25519 -C "my-linux-laptop-2026"
```

you should see an output like:
`Generating public/private ed25519 key pair.`
then it will ask for a passphrase, here you enter a secure passphrase
then it will ask you to confirm by entering it again then you will see an output thatg says

```bash
Enter file in which to save the key (/home/LOCAL_PC/.ssh/id_ed25519): 
Enter passphrase (empty for no passphrase): 
Enter same passphrase again: 
Your identification has been saved in /home/LOCAL_PC/.ssh/id_ed25519
Your public key has been saved in /home/LOCAL_PC/.ssh/id_ed25519.pub
```

> [!NOTE]
> Only the **public** key (`id_ed25519.pub`) ever leaves your local machine. The private key (`id_ed25519`) stays on your local PC, it should never be copied to the VPS, not even to root's folder.

## 🚀 Step 2: Creating non-root sudo user

**Before adding your SSH key we have to create a non-root sudo user**

Using your server as the root user is dangerous. One wrong command can break the system plus root users are always hackers first target. We are going to create a standard user and give them admin privileges (sudo) only when needed.

SSH to your VPS as the root user using the command

```bash
ssh root@your_server_ip 
```

While still logged in as root on your VPS, run the following command to create a new user (replace username with whatever you want e.g deploy, sysadmin, ITLead)

```bash
adduser sysadmin
usermod -aG sudo sysadmin
```

## 🚀 Step 3: Adding your SSH key to the non-root user

```bash
cat /home/LOCAL_PC/.ssh/id_ed25519.pub
```

above will be your public key, run this on your **local** machine, not the VPS

Now we need to add the public key to the new sysadmin user on the VPS by coping the output of the cat command to a file on the VPS. Still logged in as root, create the `.ssh` directory for the new user and open the file that would hold the public key:

```bash
mkdir -p /home/sysadmin/.ssh
nano /home/sysadmin/.ssh/authorized_keys
```

The nano command would open a text editor.
Paste the public key that you copied above into this file. It should look something like this ssh-ed25519....XXXXXX
Save and exit the file (in Nano, press CTRL+O, hit Enter, then press CTRL+X).

Finally, we must set the correct file permissions and ownership. SSH is very strict about security, and if these files are readable by anyone else on the server, or owned by the wrong user, SSH will ignore your key!

```bash
chown -R sysadmin:sysadmin /home/sysadmin/.ssh
chmod 700 /home/sysadmin/.ssh
chmod 600 /home/sysadmin/.ssh/authorized_keys
```

Now, open a new terminal on your local laptop and test that you can log in as your new user:

```bash
ssh sysadmin@your_server_ip
```

If you log in successfully without being asked for a password, you are ready to lock down the server!

## 🚀 Step 4: Hardening the SSH Configuration

in the new terminal as the the user sysadmin (or what ever username you chose)

before touching anything make a backup copy of the config first, if you mess it up later you can just copy this back over and your fine

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
```

Open the main SSH configuration file using a text editor:

```bash
sudo nano /etc/ssh/sshd_config
```

Scroll through the file and look for the following lines. You will need to change their values to no. If there is a # symbol at the beginning of the line, remove it to uncomment the setting:

1. `PasswordAuthentication no`
2. `PermitRootLogin no`
3. `PermitEmptyPasswords no`

A few notes on these settings:

- `PermitRootLogin no` is good, but test the new user first before disabling root SSH, don't set this until you've confirmed you can log in and sudo as `sysadmin`.
- `PasswordAuthentication no` can be overridden by other SSH configuration files on newer Debian/Ubuntu systems, so also check `/etc/ssh/sshd_config.d/*.conf` for a conflicting setting.
- `PermitEmptyPasswords no` is worth setting explicitly, but it is normally already the default.

Save the file and exit (Press CTRL+O, hit Enter, then press CTRL+X).

Before restarting, check the config for syntax errors:

```bash
sudo sshd -t
```

This catches syntax errors and can prevent a bad configuration from taking effect, if it prints nothing, the config is valid.

To apply these new security rules, reload the SSH service:

```bash
sudo systemctl reload ssh
```

`reload` is generally preferable to `restart` here because it re-reads the config without unnecessarily terminating and reinitializing the running service (which would drop any active SSH sessions).

## 🚀 Step 5: Setting up UFW (firewall edition)

Having ssh locked down isnt enough on its own as theres still every other port on the machine wide open instead we are going to use **UFW (Uncomplicated Firewall)** which is basically a friendly wrapper around iptables that lets you block everything except what you actually need

First install it and make sure its there

```bash
sudo apt update
sudo apt install ufw
```

then we set the default policy, deny everything coming in, allow everything going out

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

> [!WARNING]
> Do NOT enable ufw before you allow ssh through it. if you enable it first you will instantly lock yourself out the server and have to go through your host's console to fix it

so allow ssh first, technically theres an OpenSSH app profile ufw can use but that only exists on some setups so instead we just allow the port directly which works everywhere

```bash
sudo ufw allow 22/tcp
```

now we can safely turn it on

```bash
sudo ufw enable
```

it will ask you to confirm since it warns you it might disrupt existing ssh connections, just type y and hit enter since we already allowed the ssh rule above

to check everything applied correctly run

```bash
sudo ufw status verbose
```

you should see 22/tcp listed as ALLOW in the output. open a brand new terminal window (dont close your current one yet) and confirm you can still log back in, same rule as before, always keep your old session open until the new one is confirmed working

## 🚀 Step 6: Setting up fail2ban

fail2ban is a service that watches your auth logs and if it sees the same ip failing to login over and over it temporarily bans that ip at the firewall level, pairs nicely with ufw

install it with

```bash
sudo apt install fail2ban
```

fail2ban comes with a default jail.conf file but the thing is it gets overwritten anytime the package updates so instead of editing that one directly we make our own override file called jail.local

```bash
sudo nano /etc/fail2ban/jail.local
```

paste in the following to turn on the sshd jail

```ini
[sshd]
enabled = true
port = ssh
maxretry = 5
findtime = 10m
bantime = 1h
```

quick breakdown of what these actually do

- maxretry, how many failed logins before its considered an attack
- findtime, the time window those failed logins are counted within
- bantime, how long the ip gets banned for (you can set this to -1 for a permanent ban but honestly a timed ban is usually fine)

save and exit same as always (CTRL+O, Enter, then CTRL+X) then instead of just restarting it we want it enabled on boot too otherwise itll stop protecting you after your next reboot

```bash
sudo systemctl enable --now fail2ban
```

to check the sshd jail is actually running and doing its job

```bash
sudo fail2ban-client status sshd
```

this will show you the current and total failed/banned attempts. and just incase you end up banning yourself while your testing this (it happens to everyone eventually) heres how to unban your own ip

```bash
sudo fail2ban-client set sshd unbanip your_ip_address
```
