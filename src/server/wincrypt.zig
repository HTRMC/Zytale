//! Windows CryptoAPI bindings for runtime self-signed certificate generation
//! Uses crypt32.dll and ncrypt.dll to generate certificates at server startup

const std = @import("std");

const log = std.log.scoped(.wincrypt);

// Windows type aliases
pub const BOOL = i32;
pub const DWORD = u32;
pub const ULONG = u32;
pub const LONG = i32;
pub const LPCWSTR = [*:0]const u16;
pub const LPWSTR = [*:0]u16;
pub const BYTE = u8;
pub const PBYTE = [*]u8;
pub const LPCSTR = [*:0]const u8;
pub const HANDLE = *anyopaque;
pub const HCRYPTPROV_LEGACY = usize;
pub const NCRYPT_PROV_HANDLE = usize;
pub const NCRYPT_KEY_HANDLE = usize;

pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;

// Certificate context structure
pub const CERT_CONTEXT = extern struct {
    encoding_type: DWORD,
    encoded_cert: ?[*]BYTE,
    encoded_cert_len: DWORD,
    cert_info: ?*anyopaque, // PCERT_INFO
    store: ?*anyopaque, // HCERTSTORE
};

pub const PCCERT_CONTEXT = ?*const CERT_CONTEXT;

// Cryptographic blob for names
pub const CRYPT_DATA_BLOB = extern struct {
    cbData: DWORD,
    pbData: ?PBYTE,
};

pub const CERT_NAME_BLOB = CRYPT_DATA_BLOB;

// Algorithm identifier
pub const CRYPT_ALGORITHM_IDENTIFIER = extern struct {
    pszObjId: ?LPCSTR,
    Parameters: CRYPT_DATA_BLOB,
};

// CRYPT_KEY_PROV_INFO for certificate-key association
pub const CRYPT_KEY_PROV_INFO = extern struct {
    pwszContainerName: ?LPWSTR,
    pwszProvName: ?LPWSTR,
    dwProvType: DWORD,
    dwFlags: DWORD,
    cProvParam: DWORD,
    rgProvParam: ?*anyopaque,
    dwKeySpec: DWORD,
};

// Constants
pub const X509_ASN_ENCODING: DWORD = 0x00000001;
pub const PKCS_7_ASN_ENCODING: DWORD = 0x00010000;
pub const CERT_X500_NAME_STR: DWORD = 3;

// NCrypt constants
pub const MS_KEY_STORAGE_PROVIDER = std.unicode.utf8ToUtf16LeStringLiteral("Microsoft Software Key Storage Provider");
pub const NCRYPT_OVERWRITE_KEY_FLAG: DWORD = 0x00000080;
pub const NCRYPT_MACHINE_KEY_FLAG: DWORD = 0x00000020;
pub const BCRYPT_RSA_ALGORITHM = std.unicode.utf8ToUtf16LeStringLiteral("RSA");
pub const BCRYPT_ECDSA_P256_ALGORITHM = std.unicode.utf8ToUtf16LeStringLiteral("ECDSA_P256");
pub const NCRYPT_LENGTH_PROPERTY = std.unicode.utf8ToUtf16LeStringLiteral("Length");
pub const AT_KEYEXCHANGE: DWORD = 1;

// OIDs for algorithms
pub const szOID_RSA_SHA256RSA: LPCSTR = "1.2.840.113549.1.1.11";
pub const szOID_ECDSA_SHA256: LPCSTR = "1.2.840.10045.4.3.2";

// Error codes
pub const NTE_EXISTS: LONG = -0x7FF6FFAF; // 0x8009000F
pub const S_OK: LONG = 0;

// External function declarations - crypt32.dll
extern "crypt32" fn CertStrToNameW(
    encoding_type: DWORD,
    name: LPCWSTR,
    str_type: DWORD,
    reserved: ?*anyopaque,
    encoded: ?PBYTE,
    encoded_size: *DWORD,
    error_str: ?*LPCWSTR,
) callconv(.c) BOOL;

extern "crypt32" fn CertCreateSelfSignCertificate(
    prov: HCRYPTPROV_LEGACY,
    subject_issuer_blob: *const CERT_NAME_BLOB,
    flags: DWORD,
    key_prov_info: ?*const CRYPT_KEY_PROV_INFO,
    signature_alg: ?*const CRYPT_ALGORITHM_IDENTIFIER,
    start_time: ?*const SYSTEMTIME,
    end_time: ?*const SYSTEMTIME,
    extensions: ?*anyopaque,
) callconv(.c) PCCERT_CONTEXT;

extern "crypt32" fn CertFreeCertificateContext(
    cert_context: PCCERT_CONTEXT,
) callconv(.c) BOOL;

// External function declarations - ncrypt.dll
extern "ncrypt" fn NCryptOpenStorageProvider(
    provider: *NCRYPT_PROV_HANDLE,
    provider_name: LPCWSTR,
    flags: DWORD,
) callconv(.c) LONG;

extern "ncrypt" fn NCryptCreatePersistedKey(
    provider: NCRYPT_PROV_HANDLE,
    key: *NCRYPT_KEY_HANDLE,
    algorithm: LPCWSTR,
    key_name: ?LPCWSTR,
    key_spec: DWORD,
    flags: DWORD,
) callconv(.c) LONG;

extern "ncrypt" fn NCryptSetProperty(
    object: NCRYPT_KEY_HANDLE,
    property: LPCWSTR,
    input: [*]const BYTE,
    input_len: DWORD,
    flags: DWORD,
) callconv(.c) LONG;

extern "ncrypt" fn NCryptFinalizeKey(
    key: NCRYPT_KEY_HANDLE,
    flags: DWORD,
) callconv(.c) LONG;

extern "ncrypt" fn NCryptFreeObject(
    object: NCRYPT_KEY_HANDLE,
) callconv(.c) LONG;

extern "ncrypt" fn NCryptDeleteKey(
    key: NCRYPT_KEY_HANDLE,
    flags: DWORD,
) callconv(.c) LONG;

// SYSTEMTIME structure for certificate validity
pub const SYSTEMTIME = extern struct {
    wYear: u16,
    wMonth: u16,
    wDayOfWeek: u16,
    wDay: u16,
    wHour: u16,
    wMinute: u16,
    wSecond: u16,
    wMilliseconds: u16,
};

extern "kernel32" fn GetSystemTime(
    system_time: *SYSTEMTIME,
) callconv(.c) void;

/// Key type for certificate generation
pub const KeyType = enum {
    rsa_2048,
    rsa_4096,
    ecdsa_p256,
};

/// Certificate configuration
pub const CertConfig = struct {
    /// X.500 subject name (e.g., "CN=localhost")
    subject: []const u8 = "CN=localhost",
    /// Key type to use
    key_type: KeyType = .rsa_2048,
    /// Validity period in years
    validity_years: u16 = 1,
};

/// Generated certificate handle
pub const Certificate = struct {
    context: PCCERT_CONTEXT,
    key_handle: NCRYPT_KEY_HANDLE,
    provider_handle: NCRYPT_PROV_HANDLE,
    key_name_buf: [64]u16,

    pub fn deinit(self: *Certificate) void {
        if (self.context) |ctx| {
            _ = CertFreeCertificateContext(ctx);
            self.context = null;
        }

        if (self.key_handle != 0) {
            // Delete the persisted key from storage
            _ = NCryptDeleteKey(self.key_handle, 0);
            self.key_handle = 0;
        }

        if (self.provider_handle != 0) {
            _ = NCryptFreeObject(self.provider_handle);
            self.provider_handle = 0;
        }
    }
};

/// Generate a self-signed certificate using Windows CryptoAPI
pub fn generateSelfSignedCert(allocator: std.mem.Allocator, config: CertConfig) !Certificate {
    _ = allocator;

    log.info("Generating self-signed certificate...", .{});

    var cert = Certificate{
        .context = null,
        .key_handle = 0,
        .provider_handle = 0,
        .key_name_buf = undefined,
    };
    errdefer cert.deinit();

    // Generate a unique key name using timestamp for uniqueness
    // First create as UTF-8, then convert to UTF-16 for Windows API
    var key_name_u8: [64]u8 = undefined;
    const io = std.Io.Threaded.global_single_threaded.io();
    const ts = std.Io.Clock.real.now(io) catch std.Io.Timestamp{ .nanoseconds = 0 };
    const key_name_len = (std.fmt.bufPrint(&key_name_u8, "ZytaleCert-{d}", .{ts.nanoseconds}) catch {
        return error.KeyNameTooLong;
    }).len;

    // Convert to UTF-16
    const converted_len = std.unicode.utf8ToUtf16Le(&cert.key_name_buf, key_name_u8[0..key_name_len]) catch {
        return error.KeyNameEncodingFailed;
    };
    cert.key_name_buf[converted_len] = 0; // Null terminate

    // Open NCrypt storage provider
    var status = NCryptOpenStorageProvider(
        &cert.provider_handle,
        MS_KEY_STORAGE_PROVIDER.ptr,
        0,
    );
    if (status != S_OK) {
        log.err("NCryptOpenStorageProvider failed: 0x{X:0>8}", .{@as(u32, @bitCast(status))});
        return error.ProviderOpenFailed;
    }

    // Determine algorithm based on key type
    const algorithm: LPCWSTR = switch (config.key_type) {
        .rsa_2048, .rsa_4096 => BCRYPT_RSA_ALGORITHM.ptr,
        .ecdsa_p256 => BCRYPT_ECDSA_P256_ALGORITHM.ptr,
    };

    // Create persisted key (with unique name to avoid collisions)
    // Use NCRYPT_OVERWRITE_KEY_FLAG to replace if exists
    status = NCryptCreatePersistedKey(
        cert.provider_handle,
        &cert.key_handle,
        algorithm,
        @ptrCast(&cert.key_name_buf), // Use the unique key name
        AT_KEYEXCHANGE,
        NCRYPT_OVERWRITE_KEY_FLAG,
    );
    if (status != S_OK) {
        log.err("NCryptCreatePersistedKey failed: 0x{X:0>8}", .{@as(u32, @bitCast(status))});
        return error.KeyCreationFailed;
    }

    // Set key length for RSA
    if (config.key_type == .rsa_2048 or config.key_type == .rsa_4096) {
        const key_length: DWORD = switch (config.key_type) {
            .rsa_2048 => 2048,
            .rsa_4096 => 4096,
            else => unreachable,
        };
        status = NCryptSetProperty(
            cert.key_handle,
            NCRYPT_LENGTH_PROPERTY.ptr,
            @ptrCast(&key_length),
            @sizeOf(DWORD),
            0,
        );
        if (status != S_OK) {
            log.err("NCryptSetProperty (length) failed: 0x{X:0>8}", .{@as(u32, @bitCast(status))});
            return error.KeyPropertyFailed;
        }
    }

    // Finalize the key
    status = NCryptFinalizeKey(cert.key_handle, 0);
    if (status != S_OK) {
        log.err("NCryptFinalizeKey failed: 0x{X:0>8}", .{@as(u32, @bitCast(status))});
        return error.KeyFinalizeFailed;
    }

    log.info("RSA key pair generated", .{});

    // Encode subject name
    var subject_buf: [256]u8 = undefined;
    var subject_size: DWORD = subject_buf.len;

    // Convert subject to wide string
    var subject_w: [256]u16 = undefined;
    const subject_len = std.unicode.utf8ToUtf16Le(&subject_w, config.subject) catch {
        return error.SubjectEncodingFailed;
    };
    subject_w[subject_len] = 0;

    const result = CertStrToNameW(
        X509_ASN_ENCODING,
        @ptrCast(&subject_w),
        CERT_X500_NAME_STR,
        null,
        &subject_buf,
        &subject_size,
        null,
    );
    if (result == FALSE) {
        log.err("CertStrToNameW failed", .{});
        return error.SubjectEncodingFailed;
    }

    const subject_blob = CERT_NAME_BLOB{
        .cbData = subject_size,
        .pbData = &subject_buf,
    };

    // Set up key provider info to associate the NCrypt key with the certificate
    var key_prov_info = CRYPT_KEY_PROV_INFO{
        .pwszContainerName = @ptrCast(@constCast(&cert.key_name_buf)),
        .pwszProvName = @ptrCast(@constCast(MS_KEY_STORAGE_PROVIDER.ptr)),
        .dwProvType = 0, // CNG doesn't use provider type
        .dwFlags = 0,
        .cProvParam = 0,
        .rgProvParam = null,
        .dwKeySpec = AT_KEYEXCHANGE,
    };

    // Set up signature algorithm
    var sig_alg = CRYPT_ALGORITHM_IDENTIFIER{
        .pszObjId = switch (config.key_type) {
            .rsa_2048, .rsa_4096 => szOID_RSA_SHA256RSA,
            .ecdsa_p256 => szOID_ECDSA_SHA256,
        },
        .Parameters = .{ .cbData = 0, .pbData = null },
    };

    // Set up validity period
    var start_time: SYSTEMTIME = undefined;
    GetSystemTime(&start_time);

    var end_time = start_time;
    end_time.wYear += config.validity_years;

    // Create self-signed certificate
    cert.context = CertCreateSelfSignCertificate(
        0, // Use key_prov_info instead
        &subject_blob,
        0,
        &key_prov_info,
        &sig_alg,
        &start_time,
        &end_time,
        null, // No extensions
    );

    if (cert.context == null) {
        log.err("CertCreateSelfSignCertificate failed", .{});
        return error.CertCreationFailed;
    }

    log.info("Using self-signed certificate: {s}", .{config.subject});

    return cert;
}

test "generate self-signed certificate" {
    // This test only runs on Windows
    if (@import("builtin").os.tag != .windows) {
        return;
    }

    var cert = try generateSelfSignedCert(std.testing.allocator, .{
        .subject = "CN=test.local",
        .key_type = .rsa_2048,
        .validity_years = 1,
    });
    defer cert.deinit();

    try std.testing.expect(cert.context != null);
    try std.testing.expect(cert.key_handle != 0);
}
