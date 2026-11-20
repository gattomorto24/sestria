from pathlib import Path
import os,subprocess,zipfile
project=Path(__file__).resolve().parents[2]
root=Path('/tmp/orlog-android-tools')
out=root/'smoke';out.mkdir(exist_ok=True)
classes=out/'classes';classes.mkdir(exist_ok=True)
sdk=root/'sdk';bt=sdk/'build-tools/35.0.1';android=sdk/'platforms/android-36/android.jar'
jdk=Path('/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home')
env=os.environ.copy();env['JAVA_HOME']=str(jdk)
def run(args):subprocess.run([str(a) for a in args],check=True,env=env)
run([jdk/'bin/javac','-source','17','-target','17','-classpath',android,'-d',classes,project/'tests/native/SestriaSmoke.java'])
run([jdk/'bin/jar','cf',out/'test.jar','-C',classes,'.'])
run([bt/'d8','--lib',android,'--min-api','24','--output',out,out/'test.jar'])
run([bt/'aapt','package','-f','-M',project/'tests/native/AndroidManifest.xml','-I',android,'-F',out/'smoke-unsigned.apk'])
with zipfile.ZipFile(out/'smoke-unsigned.apk','a') as z:z.write(out/'classes.dex','classes.dex')
run([bt/'zipalign','-f','4',out/'smoke-unsigned.apk',out/'smoke.apk'])
run([bt/'apksigner','sign','--ks',root/'debug.keystore','--ks-pass','pass:android','--ks-key-alias','androiddebugkey',out/'smoke.apk'])
print(out/'smoke.apk')
