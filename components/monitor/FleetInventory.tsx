'use client';
// SPDX-License-Identifier: BUSL-1.1
import type {ClusterSnapshot} from '@/lib/cluster';
import {Card} from './primitives';
export function FleetInventory({cluster}:{cluster:ClusterSnapshot}){return <Card><div className="section-bar"><h3>Fleet inventory</h3><span className="count">{cluster.nodes.length}</span></div><div className="table-scroll"><table className="data-table"><thead><tr><th>Machine</th><th>Group</th><th>Site</th><th>Tags</th><th>Agent</th><th>Health</th></tr></thead><tbody>{cluster.nodes.map(n=>{const inv=n.inventory,health=n.agentHealth;return <tr key={n.id}><td>{n.name}</td><td>{n.group??'—'}</td><td>{n.site??'—'}</td><td>{n.tags?.join(', ')||'—'}</td><td>{inv?.agentVersion??'—'}</td><td>{health?.healthy===false?'Degraded':n.online?'Healthy':'Offline'}</td></tr>})}</tbody></table></div></Card>}
