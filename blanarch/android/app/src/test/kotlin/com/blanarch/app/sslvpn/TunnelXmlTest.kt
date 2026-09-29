package com.blanarch.app.sslvpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TunnelXmlTest {
    private val specExample = """
        <?xml version='1.0' encoding='utf-8'?>
        <sslvpn-tunnel ver='2' dtls='1' patch='1'>
          <dtls-config heartbeat-interval='10' heartbeat-fail-count='10' heartbeat-idle-timeout='3' client-hello-timeout='10'/>
          <tunnel-method value='ppp'/>
          <tunnel-method value='tun'/>
          <fos platform='FG100F' major='7' minor='2' patch='8' build='1639' branch='1639'/>
          <client-config save-password='off' keep-alive='on' auto-connect='off'/>
          <ipv4>
            <dns ip='10.0.0.53'/>
            <dns ip='10.0.0.54'/>
            <dns domain='corp.example'/>
            <assigned-addr ipv4='10.212.134.7'/>
            <split-tunnel-info>
              <addr ip='10.10.0.0' mask='255.255.0.0'/>
              <addr ip='192.168.50.0' mask='255.255.255.0'/>
            </split-tunnel-info>
          </ipv4>
          <idle-timeout val='3600'/>
          <auth-timeout val='28800'/>
        </sslvpn-tunnel>
    """.trimIndent()

    @Test
    fun `parses the spec example`() {
        val c = TunnelXml.parse(specExample)
        assertEquals("10.212.134.7", c.assignedIp)
        assertEquals(listOf("10.0.0.53", "10.0.0.54"), c.dns)
        assertEquals("corp.example", c.dnsSuffix)
        assertEquals(listOf("10.10.0.0" to "255.255.0.0", "192.168.50.0" to "255.255.255.0"), c.routes)
    }

    @Test
    fun `no split tunnel info means empty routes`() {
        val xml = "<sslvpn-tunnel><ipv4><dns ip=\"10.0.0.53\"/>" +
            "<assigned-addr ipv4=\"10.1.1.1\"/></ipv4></sslvpn-tunnel>"
        val c = TunnelXml.parse(xml)
        assertTrue(c.routes.isEmpty())
        assertEquals(listOf("10.0.0.53"), c.dns)
        assertEquals("10.1.1.1", c.assignedIp)
        assertNull(c.dnsSuffix)
    }

    @Test
    fun `empty split tunnel info means empty routes`() {
        val c = TunnelXml.parse("<sslvpn-tunnel><ipv4><split-tunnel-info/></ipv4></sslvpn-tunnel>")
        assertTrue(c.routes.isEmpty())
        val d = TunnelXml.parse("<sslvpn-tunnel><ipv4><split-tunnel-info></split-tunnel-info></ipv4></sslvpn-tunnel>")
        assertTrue(d.routes.isEmpty())
    }

    @Test
    fun `several search domains are kept`() {
        val c = TunnelXml.parse("<ipv4><dns domain='a.example;b.example'/><dns domain=\"c.example\"/></ipv4>")
        assertEquals("a.example;b.example;c.example", c.dnsSuffix)
    }

    @Test
    fun `addr outside split tunnel info and ipv6 sections are ignored`() {
        val xml = "<t><addr ip='1.2.3.4' mask='255.255.255.255'/><ipv6><dns ip='fd00::1'/>" +
            "<split-tunnel-info><addr ip='fd00::' mask='64'/></split-tunnel-info></ipv6></t>"
        val c = TunnelXml.parse(xml)
        assertTrue(c.routes.isEmpty())
        assertTrue(c.dns.isEmpty())
    }
}
