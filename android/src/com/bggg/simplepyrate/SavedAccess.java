package com.bggg.simplepyrate;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import java.io.*;
import java.nio.file.Files;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class SavedAccess {
    private static final String ALIAS="SimplePyrateSavedSourceAccessV1";
    private static final int LIMIT=1024*1024;
    private final File blob;
    SavedAccess(Context context){blob=new File(context.getNoBackupFilesDir(),"saved-source-access.v1");}
    boolean exists(){return blob.isFile();}
    private static KeyStore store()throws Exception{
        KeyStore store=KeyStore.getInstance("AndroidKeyStore");
        store.load(null);return store;
    }
    private static SecretKey key(boolean create)throws Exception{
        KeyStore store=store();
        if(store.containsAlias(ALIAS))return (SecretKey)store.getKey(ALIAS,null);
        if(!create)throw new IOException("Saved sign-in is no longer available.");
        KeyGenerator generator=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).build());
        return generator.generateKey();
    }
    void save(Access access)throws Exception{
        if(!access.active())throw new IOException("Import account cookies or enter a PO token first.");
        ByteArrayOutputStream raw=new ByteArrayOutputStream();
        try(DataOutputStream out=new DataOutputStream(raw)){
            out.writeUTF(access.po);
            out.writeInt(access.cookies==null?-1:access.cookies.length);
            if(access.cookies!=null)out.write(access.cookies);
        }
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE,key(true));
        byte[] iv=cipher.getIV(), encrypted=cipher.doFinal(raw.toByteArray());
        if(iv.length!=12)throw new IOException("Could not protect the source credentials.");
        File stage=File.createTempFile("source-access-", ".part",blob.getParentFile());
        try{
            try(FileOutputStream f=new FileOutputStream(stage)){f.write(iv);f.write(encrypted);f.getFD().sync();}
            RuntimeTools.commit(stage,blob);
        } finally {stage.delete();}
    }
    Access load()throws Exception{
        if(!exists()||blob.length()<28||blob.length()>LIMIT+65536)throw new IOException("No saved sign-in is available.");
        byte[] bytes=Files.readAllBytes(blob.toPath());
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE,key(false),new GCMParameterSpec(128,bytes,0,12));
        byte[] raw=cipher.doFinal(bytes,12,bytes.length-12);
        try(DataInputStream in=new DataInputStream(new ByteArrayInputStream(raw))){
            String token=in.readUTF();
            int size=in.readInt();
            if(size < -1 || size>LIMIT)throw new IOException("Saved sign-in is invalid.");
            byte[] cookies=size<0?null:new byte[size];
            if(cookies!=null)in.readFully(cookies);
            if(in.read()!=-1)throw new IOException("Saved sign-in is invalid.");
            return new Access(token,cookies);
        } finally {java.util.Arrays.fill(raw,(byte)0);}
    }
    void clear()throws Exception{
        Files.deleteIfExists(blob.toPath());
        KeyStore store=store();
        if(store.containsAlias(ALIAS))store.deleteEntry(ALIAS);
    }
}
