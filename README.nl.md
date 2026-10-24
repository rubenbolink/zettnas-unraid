# zettnas-unraid

**Unraid op een Zettlab NAS: van een USB-stick gemaakt op Windows tot een stabiel systeem dat niet meer uitvalt, met zowel de CPU- als de HDD-fans geregeld.**

> Getest op een **Zettlab D6 Ultra** (Intel Core Ultra 5 125H) met **Unraid 7.3.4**. Andere modellen (D4 / D6 / D8) lijken waarschijnlijk, maar zijn **niet getest**.
>
> 🇬🇧 English version (uitgebreider): [README.md](README.md)

> ⚠️ **Disclaimer:** gebruik op eigen risico. Het fan-script schrijft rechtstreeks naar fysiek geheugen (`/dev/mem`). Geen garantie, zie [LICENSE](LICENSE).

## Waarom dit nodig is

1. **Piepen en harde reboot na een paar minuten**: ZettOS voedt een hardware-watchdog; Unraid heeft daar geen driver voor. → Watchdog uitzetten in de BIOS.
2. **Oververhitting en uitschakelen (vaak binnen ~1 minuut)**: de fans hangen aan de embedded controller; onder Unraid blijft de CPU-fan **uit**. → Gebruik het script uit deze repo.

## 1. Benodigdheden

- **USB-stick** (8–32 GB). Niet elke stick wordt bij het opstarten herkend. Een **SanDisk Cruzer Fit** werkte, de eerste stick niet. Bij *"boot device not found"*: probeer een andere stick.
- **Unraid USB Creator** op Windows (of handmatig: FAT32, label `UNRAID`, `make_bootable.bat` als administrator).
- Trial- of licentiesleutel; die is gekoppeld aan de GUID van de stick.
- Monitor en toetsenbord voor de BIOS.

## 2. BIOS (F2 / F12)

Druk bij het aanzetten op **F2**:

| Instelling | Waarde | Waarom |
|---|---|---|
| **Secure Boot** | **Uit** | Unraid-bootloader is niet gesigneerd |
| **Watchdog Timer (WDT)** | **Uit** | **Essentieel**, anders piep + reboot na enkele minuten |
| **HDD power on sequence** | **Aan** | Schijven gespreid opstarten |
| **Bootvolgorde** | **USB eerst** | Automatisch Unraid starten |

**F12** bij het aanzetten = eenmalig bootmenu om de USB-stick te kiezen.
De WDT-stap komt uit de handleiding [henryxwong/zettlab-ubuntu](https://github.com/henryxwong/zettlab-ubuntu).

## 3. Interne SSD

- **Optie A (aanbevolen):** laat de originele ZettOS-SSD onaangeroerd liggen als terugvaloptie en plaats een losse NVMe als Unraid-cache.
- **Optie B:** hergebruik/wis de originele SSD als cache. ZettOS is dan weg.

**Let op:** de installer van Unraid 7.x kan *internal boot* aanbieden en de boot op de NVMe zetten (ZFS-pool `flash`). Wil je van USB booten, kies dan **USB**. Herstel: kopieer `/boot/config` naar de USB-stick, verwijder `config/pools/boot.cfg`, boot van USB en voer uit:
```bash
zpool export flash
wipefs -a /dev/nvme0n1    # ⚠️ WIST ALLES op deze NVMe — controleer eerst met lsblk
```

## 4. Hardware-valkuilen

- **Geen HDD's zichtbaar na openen van de kast?** Sluit de kabel van het **SATA-bridgebord** opnieuw aan.
- **Schijf ontbreekt na verplaatsen?** `dmesg` toont `SATA link down`: uitzetten, schijf stevig terugduwen, opnieuw opstarten. Start de array pas als alle schijven er zijn.

## 5. Installatie en array

1. Boot van USB, open de webinterface, stel het root-wachtwoord in, start de trial.
2. Herken schijven aan hun **serienummer** (letters verschuiven, de stick wordt `sda`).
3. 1 parity + data-schijven, NVMe als cache. Start en **formatteer**.
4. Docker in **directory**-modus; shares `appdata` en `system` op **Cache only**.

## 6. Fan-regeling

EC-basisadres `0xFE0B0456` via `/dev/mem`. PWM 0–183. PWM-registers: `+2` en `+5` (schijffans), `+8` (CPU-fan). RPM 16-bit big-endian op `+0`, `+3`, `+6`. Plugins als FanCtrl Plus, Dynamix AutoFan en it87/nct-drivers **werken niet** op dit bord.

Installeren:
```bash
wget -O /boot/config/zettlab-fans.sh https://raw.githubusercontent.com/rubenbolink/zettnas-unraid/main/zettlab-fans.sh
echo 'nohup bash /boot/config/zettlab-fans.sh >/dev/null 2>&1 &' >> /boot/config/go
nohup bash /boot/config/zettlab-fans.sh >/dev/null 2>&1 &
cat /var/log/zettlab-fans.log
```

Afstellen: pas de variabelen bovenin aan (`D_MIN=70 D_MAX=183 T_LO=35 T_HI=48 T_PANIC=55 C_MIN=90 C_MAX=183 C_LO=50 C_HI=80 INTERVAL=10`), daarna:
```bash
pkill -f zettlab-fans.sh
nohup bash /boot/config/zettlab-fans.sh >/dev/null 2>&1 &
```
Bij stoppen zet het script alle fans op vol. Testen: `bash fan-test.sh` (uitlezen) of `bash fan-test.sh 120` (vaste PWM; stop eerst het script). RPM uitlezen werkt (bijv. `1901 1879 2933`); `0` betekent dat de fan stilstaat, bijv. de CPU-fan op EC-auto.

## 7. Controlelijst

- [ ] Geen piep/reboot na 15 minuten
- [ ] `/var/log/zettlab-fans.log` wordt elke 10 s bijgewerkt
- [ ] CPU-fan draait hoorbaar; HDD's onder ~45 °C tijdens parity-sync
- [ ] Alle schijven aanwezig; script start na reboot automatisch

## 8. Problemen oplossen

| Symptoom | Oorzaak | Oplossing |
|---|---|---|
| Piep + reboot na paar minuten | Watchdog | F2 → WDT uit |
| Oververhitting na ~1 minuut | Fans niet geregeld | Installeer het script |
| CPU-fan draait niet | EC-auto houdt hem uit | Controleer of het script draait |
| Geen schijven | SATA-bridgekabel los | Opnieuw aansluiten |
| "Boot device not found" | Stick niet ondersteund | Andere stick proberen |

## 9. Extra's (optioneel)

- **Intel iGPU voor Ollama:** officiële `ollama/ollama`, device `/dev/dri`, `OLLAMA_VULKAN=1` en `OLLAMA_IGPU_ENABLE=1`.
- **Tailscale:** voeg de Tailscale-interface toe onder Settings → Management Access en herstart sshd.
- **UPS via Synology:** NUT-plugin als *Netclient*, UPS `ups`, gebruiker `monuser`, wachtwoord `secret`.

## Credits

[henryxwong/zettlab-ubuntu](https://github.com/henryxwong/zettlab-ubuntu) · [haveacry/zettlab-d8-fans](https://github.com/haveacry/zettlab-d8-fans) · [fr0styx/zettnas-toolkit](https://github.com/fr0styx/zettnas-toolkit)
