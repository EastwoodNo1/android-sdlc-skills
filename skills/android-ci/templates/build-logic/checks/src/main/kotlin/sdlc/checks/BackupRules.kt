package sdlc.checks

import org.w3c.dom.Element
import org.xml.sax.SAXException
import sdlc.checks.SecureXml.elements

object BackupRules {
    private val sections = listOf("full-backup-content", "cloud-backup", "device-transfer")

    fun validate(
        xml: String,
        allowed: Set<String>,
    ): List<String> {
        val root =
            try {
                SecureXml.parse(xml)
            } catch (e: SAXException) {
                return listOf("backup rules are not valid XML: ${e.message}")
            }
        val present = sections.flatMap { name -> sectionsNamed(root, name).map { name to it } }
        if (present.isEmpty()) return listOf("no backup section found")
        return present.flatMap { (name, section) -> sectionErrors(name, section, allowed) }
    }

    private fun sectionsNamed(
        root: Element,
        name: String,
    ) = (listOf(root) + root.getElementsByTagName("*").elements()).filter { it.tagName == name }

    private fun sectionErrors(
        name: String,
        section: Element,
        allowed: Set<String>,
    ): List<String> {
        val includes = section.getElementsByTagName("include").elements()
        val found = includes.map { it.getAttribute("path") }.toSet()
        val perInclude =
            includes.flatMap { include ->
                val path = include.getAttribute("path")
                listOfNotNull(
                    "$name: include domain \"${include.getAttribute("domain")}\" for $path must be \"file\""
                        .takeIf { include.getAttribute("domain") != "file" },
                    "$name: include path \"$path\" is not allowed".takeIf { path !in allowed },
                )
            }
        return perInclude + allowed.filter { it !in found }.sorted().map { "$name: required include $it is missing" }
    }
}
