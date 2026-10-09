// SPDX-License-Identifier: BUSL-1.1
import {BatteryMedium,Bell,Box,Cpu,FolderCode,Gauge,HardDrive,Layers,MemoryStick,Network,Server,Settings} from 'lucide-react';

export const views=[
  {id:'overview',label:'Overview',icon:Gauge,section:'Monitor',subtitle:'Your system at a glance'},
  {id:'cluster',label:'Mac cluster',icon:Server,section:'Monitor',subtitle:'Machines and their telemetry, read-only'},
  {id:'cpu',label:'CPU',icon:Cpu,section:'Monitor',subtitle:'Processor load and the apps driving it'},
  {id:'memory',label:'Memory',icon:MemoryStick,section:'Monitor',subtitle:'Physical memory and the largest consumers'},
  {id:'disk',label:'Disk',icon:HardDrive,section:'Monitor',subtitle:'Root volume capacity'},
  {id:'network',label:'Network',icon:Network,section:'Monitor',subtitle:'Throughput across host interfaces'},
  {id:'battery',label:'Battery',icon:BatteryMedium,section:'Monitor',subtitle:'Reported battery charge'},
  {id:'applications',label:'Applications',icon:Layers,section:'Workloads',subtitle:'Processes grouped by application'},
  {id:'containers',label:'Containers',icon:Box,section:'Workloads',subtitle:'Docker and Podman workloads'},
  {id:'projects',label:'Projects',icon:FolderCode,section:'Workloads',subtitle:'Developer servers by project folder'},
  {id:'alerts',label:'Alerts',icon:Bell,section:'System',subtitle:'Threshold checks on the latest sample'},
  {id:'settings',label:'Settings',icon:Settings,section:'System',subtitle:'Appearance, alerts and data'},
] as const;

export type ViewId=typeof views[number]['id'];
export const sections=['Monitor','Workloads','System'] as const;
export const palette={cpu:'var(--chart-cpu)',memory:'var(--chart-memory)',disk:'var(--chart-disk)',network:'var(--chart-network)',upload:'var(--chart-upload)',battery:'var(--chart-battery)',containers:'var(--chart-containers)',apps:'var(--chart-apps)'};
