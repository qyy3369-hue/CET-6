using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace Goals.Windows.Services;

public sealed class WindowsCredentialStore
{
    private const string TargetName = "GoalsStudyDesk.DeepSeekApiKey";
    private const uint CredTypeGeneric = 1;
    private const uint CredPersistLocalMachine = 2;

    public bool HasKey => !string.IsNullOrWhiteSpace(Read());

    public void Save(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length < 8) throw new ArgumentException("密钥长度不正确。", nameof(value));

        var bytes = Encoding.UTF8.GetBytes(trimmed);
        var blob = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new NativeCredential
            {
                Type = CredTypeGeneric,
                TargetName = TargetName,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = CredPersistLocalMachine,
                UserName = Environment.UserName
            };
            if (!CredWrite(ref credential, 0))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "无法写入 Windows 凭据管理器。");
        }
        finally
        {
            for (var i = 0; i < bytes.Length; i++) Marshal.WriteByte(blob, i, 0);
            Array.Clear(bytes);
            Marshal.FreeHGlobal(blob);
        }
    }

    public string? Read()
    {
        if (!CredRead(TargetName, CredTypeGeneric, 0, out var pointer)) return null;
        try
        {
            var credential = Marshal.PtrToStructure<NativeCredential>(pointer);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0) return null;
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            try { return Encoding.UTF8.GetString(bytes); }
            finally { Array.Clear(bytes); }
        }
        finally
        {
            CredFree(pointer);
        }
    }

    public void Delete() => CredDelete(TargetName, CredTypeGeneric, 0);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeCredential
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref NativeCredential credential, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);
}
