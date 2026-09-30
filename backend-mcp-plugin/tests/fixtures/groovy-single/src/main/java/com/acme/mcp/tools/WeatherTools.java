package com.acme.mcp.tools;

public class WeatherTools {
    @Tool(description = "Current weather")
    public String weather(String city) { return city; }
}
