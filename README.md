# SSH hardening guide

A technical guide that shows how to secure a Linux VPS, ensuring strict SSH endpoint isolation and disabling root vulnerabilities and enable automated firewall protections  

---

## 🚀 Step 1: Generate your local SSH key (linux edition)

Using a Password isnt secure enough as it is possible to brute force and guess the password instead we will use the **Ed25519 Curve** which offers better cyrptographic strength and offers more performance than legacy RSA keys

On your local (Actual) linux PC :

```bash
ssh-keygen -t ed25519 -C "my-linux-laptop-2026"
```

you should see an output like:
`Generating public/private ed25519 key pair.`
then it will ask for a passphrase, here you enter a secure passphrase 
then it will ask you to  confirm by entering it again thenyou will see an output thatg says 

```bash
Enter file in which to save the key (/home/user/.ssh/id_ed25519): 
Enter passphrase (empty for no passphrase): 
Enter same passphrase again: 
Your identification has been saved in /home/user/.ssh/id_ed25519
Your public key has been saved in /home/user/.ssh/id_ed25519.pub
```

## Step 2: Setting up the SSH key

```bash
cat /home/user/.ssh/id_ed25519.pub
```

above will be your public key as there were two keys that were generated from the command executed above

> [!WARNING]
> Ensure to keep your private key safe and secure as the generated key pair were public and private keys 

Now we need to  add the public key to the VPS by coping the output of the cat command to a file on the VPS

SSH to your VPS you have created as the root user using the command 

```bash
ssh root@your_server_ip 
```

once logged in we will create a hidden .ssh directory and the file that would hold the public key 

```bash
mkdir -p ~/.ssh
nano ~/.ssh/authorized_keys
```

The nano command would open a text editor. 
Paste the public key that you copied in **Step 2** into this file. It should look something like this  ssh-ed25519....XXXXXX
Save and exit the file (in Nano, press CTRL+S, hit Enter, then press CTRL+X).

Finally, we must set the correct file permissions. SSH is very strict about security, and if these files are readable by anyone else on the server, SSH will ignore your key!

Run these two commands to lock down the permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

## 🚀 Creating non-root sudo user

** Before disabling password login we have to create a non-root sudo user ** 
Using your server as the root user is dangerous. One wrong command can break the system plus  root users are always hackers first target. We are going to create a standard user and give them admin privileges (sudo) only when needed.

While still logged in as root on your VPS, run the following command to create a new user (replace username with whatever you want e.g deploy, sysadmin, ITLead)


```bash
adduser sysadmin
usermod -aG sudo sysadmin
```

### 🚀 Transfering ssh key into the user

we put your SSH key in the root account's folder. We need to copy that key over to your new user(sys admin) so you can log in as them. Run these commands (remember to replace sysadmin with your chosen username):

```bash
cp -r ~/.ssh /home/sysadmin/
chown -R sysadmin:sysadmin /home/sysadmin/.ssh
```

Now, open a new terminal on your local laptop and test that you can log in as your new user:

```bash
ssh sysadmin@your_server_ip
```

If you log in successfully without being asked for a password, you are ready to lock down the server!

## 🚀 Hardening the SSH Configuration

in the new terminal as the the user sysadmin (or what ever username you chose)
Open the main SSH configuration file using a text editor:

```bash
sudo nano /etc/ssh/sshd_config
```

Scroll through the file and look for the following lines. You will need to change their values to no. If there is a # symbol at the beginning of the line, remove it to uncomment the setting:

1. ```PasswordAuthentication no```
2. `PermitRootLogin no`
3. `PermitEmptyPasswords no`

Save the file and exit (Press CTRL+S, hit Enter, then press CTRL+X).

To apply these new security rules, restart the SSH service:

```bash
sudo systemctl restart ssh
```

> [!IMPORTANT]
> Do not close your current terminal window! Before you log out, open a brand new terminal window on your laptop and try to log in to your VPS. If you made a mistake, your current active session is your only way to fix it without getting completely locked out of your server.
