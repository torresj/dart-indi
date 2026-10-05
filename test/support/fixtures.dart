/// Realistic INDI traffic in the format libindi drivers produce.
///
/// Kept as Dart so tests also run on the web.
const String sessionXml = r'''
<defSwitchVector
  device='Telescope Simulator'
  name='CONNECTION'
  label='Connection'
  group='Main Control'
  state='Idle'
  perm='rw'
  rule='OneOfMany'
  timeout='60'
  timestamp='2026-10-04T20:15:01'>
    <defSwitch
      name='CONNECT'
      label='Connect'>
Off
    </defSwitch>
    <defSwitch
      name='DISCONNECT'
      label='Disconnect'>
On
    </defSwitch>
</defSwitchVector>
<defTextVector
  device='Telescope Simulator'
  name='DRIVER_INFO'
  label='Driver Info'
  group='General Info'
  state='Idle'
  perm='ro'
  timeout='60'
  timestamp='2026-10-04T20:15:01'>
    <defText
      name='DRIVER_NAME'
      label='Name'>
Telescope Simulator
    </defText>
    <defText
      name='DRIVER_EXEC'
      label='Exec'>
indi_simulator_telescope
    </defText>
    <defText
      name='DRIVER_VERSION'
      label='Version'>
1.0
    </defText>
    <defText
      name='DRIVER_INTERFACE'
      label='Interface'>
5
    </defText>
</defTextVector>
<defNumberVector
  device='Telescope Simulator'
  name='EQUATORIAL_EOD_COORD'
  label='Eq. Coordinates'
  group='Main Control'
  state='Idle'
  perm='rw'
  timeout='60'
  timestamp='2026-10-04T20:15:02'>
    <defNumber
      name='RA'
      label='RA (hh:mm:ss)'
      format='%010.6m'
      min='0'
      max='24'
      step='0'>
5.5916666666666668
    </defNumber>
    <defNumber
      name='DEC'
      label='DEC (dd:mm:ss)'
      format='%010.6m'
      min='-90'
      max='90'
      step='0'>
-5.3911111111111111
    </defNumber>
</defNumberVector>
<message device='Telescope Simulator' timestamp='2026-10-04T20:15:02' message='[INFO] Telescope &apos;simulator&apos; is online &amp; ready. Temp &lt; 5 °C '/>
<defLightVector
  device='Telescope Simulator'
  name='STATUS'
  label='Status'
  group='Main Control'
  state='Idle'
  timestamp='2026-10-04T20:15:02'>
    <defLight
      name='TRACKING'
      label='Tracking'>
Ok
    </defLight>
    <defLight
      name='PARKED'
      label='Parked'>
Idle
    </defLight>
</defLightVector>
<defBLOBVector
  device='CCD Simulator'
  name='CCD1'
  label='Image Data'
  group='Image Info'
  state='Idle'
  perm='ro'
  timeout='60'
  timestamp='2026-10-04T20:15:03'>
    <defBLOB
      name='CCD1'
      label='Image'/>
</defBLOBVector>
<setNumberVector
  device='Telescope Simulator'
  name='EQUATORIAL_EOD_COORD'
  state='Busy'
  timeout='60'
  timestamp='2026-10-04T20:15:04'>
    <oneNumber
      name='RA'>
      5:30:00
    </oneNumber>
    <oneNumber
      name='DEC'>
      -5.25
    </oneNumber>
</setNumberVector>
<setBLOBVector
  device='CCD Simulator'
  name='CCD1'
  state='Ok'
  timeout='60'
  timestamp='2026-10-04T20:15:05'>
  <oneBLOB
    name='CCD1'
    size='11'
    enclen='16'
    format='.fits'>
SGVsbG8g
V29ybGQ=
  </oneBLOB>
</setBLOBVector>
<delProperty device='Telescope Simulator' name='STATUS' timestamp='2026-10-04T20:15:06'/>
<pingRequest uid='42' />
''';
