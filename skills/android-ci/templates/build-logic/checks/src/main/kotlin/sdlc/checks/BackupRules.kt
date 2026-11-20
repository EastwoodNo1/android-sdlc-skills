package sdlc.checks

import org.w3c.dom.Element
import org.xml.sax.SAXException
import sdlc.checks.SecureXml.elements

object BackupRules {
    private val sections = listOf("full-backup-content", "cloud-backup", "device-transfer", "cross-platform-transfer")
    private val requiredInExtractionRules = listOf("cloud-backup", "device-transfer")

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
        val missing =
            if (root.tagName == "data-extraction-rules") {
                requiredInExtractionRules
                    .filter { required -> present.none { it.first == required } }
                    .map { "data-extraction-rules: $it section is missing" }
            } else {
                emptyList()
            }
        if (present.isEmpty() && missing.isEmpty()) return listOf("no backup section found")
        return missing + present.flatMap { (name, section) -> sectionErrors(name, section, allowed) }
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
        val paths = includes.map { it.getAttribute("path") }
        val found = paths.toSet()
        val duplicates =
            paths
                .filter { it.isNotBlank() }
                .groupingBy { it }
                .eachCount()
                .filterValues { it > 1 }
                .keys
                .sorted()
                .map { "$name: duplicate include $it" }
        val perInclude =
            includes.flatMap { include ->
                val path = include.getAttribute("path")
                if (path.isBlank()) return@flatMap listOf("$name: include path is empty")
                listOfNotNull(
                    "$name: include domain \"${include.getAttribute("domain")}\" for $path must be \"file\""
                        .takeIf { include.getAttribute("domain") != "file" },
                    "$name: include path \"$path\" is not allowed".takeIf { path !in allowed },
                )
            }
        return perInclude + duplicates + allowed.filter { it !in found }.sorted().map { "$name: required include $it is missing" }
    }
}
