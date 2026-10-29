package sdlc.checks

import org.w3c.dom.Element
import org.w3c.dom.NodeList
import org.xml.sax.InputSource
import org.xml.sax.helpers.DefaultHandler
import java.io.StringReader
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory

internal object SecureXml {
    fun parse(xml: String): Element {
        val factory = DocumentBuilderFactory.newInstance()
        factory.isNamespaceAware = true
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        val builder = factory.newDocumentBuilder()
        builder.setErrorHandler(DefaultHandler())
        return builder.parse(InputSource(StringReader(xml))).documentElement
    }

    fun NodeList.elements() = (0 until length).map { item(it) as Element }
}
