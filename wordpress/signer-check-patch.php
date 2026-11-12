<?php
/*
 * PATCH for wp-content/plugins/eyvan-release-manager/eyvan-release-manager.php
 * (class PayamYar_Site_Releases) — prevents uploading an APK that is not signed
 * with the permanent PayamYar certificate.
 *
 * In validate_archive(), REPLACE the last two lines:
 *
 *         $zip->close();
 *         return $valid ? true : new WP_Error('invalid_apk', 'فایل باید APK اندروید معتبر یا ZIP شامل دقیقاً یک APK باشد.');
 *     }
 *
 * WITH everything below (the rest of validate_archive + the new apk_signer_sha256()).
 */

        if (!$valid) {
            $zip->close();
            return new WP_Error('invalid_apk', 'فایل باید APK اندروید معتبر یا ZIP شامل دقیقاً یک APK باشد.');
        }
        // Signing certificate must be the permanent PayamYar key; otherwise Android would
        // refuse the upgrade and users could be tempted to uninstall and lose local data.
        $apk_path = $file;
        $temp_apk = '';
        if ($ext === 'zip') {
            for ($i = 0; $i < $zip->numFiles; $i++) {
                $name = (string) $zip->getNameIndex($i);
                if (preg_match('/\.apk$/i', $name) && substr($name, -1) !== '/') {
                    $temp_apk = wp_tempnam('payamyar-inner.apk');
                    $in = $zip->getStream($name);
                    $out = $in ? @fopen($temp_apk, 'wb') : false;
                    if ($in && $out) { stream_copy_to_stream($in, $out, self::MAX_BYTES + 1); }
                    if ($in) fclose($in);
                    if ($out) fclose($out);
                    $apk_path = $temp_apk;
                    break;
                }
            }
        }
        $zip->close();
        $signer = self::apk_signer_sha256($apk_path);
        if ($temp_apk) @unlink($temp_apk);
        if (is_wp_error($signer)) return $signer;
        if (!hash_equals(self::RELEASE_SIGNER, $signer)) {
            return new WP_Error('wrong_signer', 'امضای این APK با گواهی رسمی پیامیار یکسان نیست (اثر انگشت: ' . $signer . '). فقط خروجی امضاشده GitHub Actions رسمی را بارگذاری کنید.');
        }
        return true;
    }

    /**
     * Reads the signer certificate from the APK Signing Block (scheme v3 preferred, else v2)
     * and returns its SHA-256 in upper-case hex. This is a consistency gate for administrators;
     * Android performs the full cryptographic verification at install time.
     */
    public static function apk_signer_sha256($file) {
        $fail = new WP_Error('unsigned_apk', 'امضای دیجیتال APK (طرح v2/v3) پیدا نشد؛ فایل امضاشده رسمی را بارگذاری کنید.');
        $fh = @fopen($file, 'rb');
        if (!$fh) return $fail;
        $size = filesize($file);
        $tail_len = (int) min($size, 65557);
        fseek($fh, $size - $tail_len);
        $tail = fread($fh, $tail_len);
        $eocd = strrpos($tail, "PK\x05\x06");
        if ($eocd === false || strlen($tail) < $eocd + 22) { fclose($fh); return $fail; }
        $cd_offset = unpack('V', substr($tail, $eocd + 16, 4))[1];
        if ($cd_offset < 32 || $cd_offset > $size) { fclose($fh); return $fail; }
        fseek($fh, $cd_offset - 24);
        $footer = fread($fh, 24);
        if (substr($footer, 8, 16) !== 'APK Sig Block 42') { fclose($fh); return $fail; }
        $block_size = unpack('P', substr($footer, 0, 8))[1];
        if ($block_size < 24 || $block_size > 16 * 1048576 || $block_size + 8 > $cd_offset) { fclose($fh); return $fail; }
        fseek($fh, $cd_offset - $block_size - 8);
        $block = fread($fh, $block_size + 8);
        fclose($fh);
        $pos = 8; $end = strlen($block) - 24; $found = [];
        while ($pos + 12 <= $end) {
            $len = unpack('P', substr($block, $pos, 8))[1];
            if ($len < 4 || $pos + 8 + $len > $end) break;
            $id = unpack('V', substr($block, $pos + 8, 4))[1];
            $found[$id] = substr($block, $pos + 12, $len - 4);
            $pos += 8 + $len;
        }
        $value = $found[0xf05368c0] ?? ($found[0x7109871a] ?? null);
        if ($value === null) return $fail;
        $read = function ($buf, &$off) {
            if ($off + 4 > strlen($buf)) return null;
            $n = unpack('V', substr($buf, $off, 4))[1];
            if ($off + 4 + $n > strlen($buf)) return null;
            $out = substr($buf, $off + 4, $n); $off += 4 + $n; return $out;
        };
        $o = 0; $signers = $read($value, $o);
        $o = 0; $signer = $signers === null ? null : $read($signers, $o);
        $o = 0; $signed = $signer === null ? null : $read($signer, $o);
        if ($signed === null) return $fail;
        $o = 0; $read($signed, $o); $certs = $read($signed, $o); // digests, then certificates
        if ($certs === null) return $fail;
        $o = 0; $cert = $read($certs, $o);
        if (!$cert) return $fail;
        return strtoupper(hash('sha256', $cert));
    }
