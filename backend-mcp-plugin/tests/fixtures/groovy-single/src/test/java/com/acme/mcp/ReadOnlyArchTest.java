package com.acme.mcp;

class ReadOnlyArchTest {
    ArchRule rule = noClasses().should().callMethod(RestClient.class, "put");
}
