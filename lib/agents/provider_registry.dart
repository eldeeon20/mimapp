/// Registro de proveedores IA (estilo FilosoIA): todos OpenAI-compatibles,
/// un solo cliente HTTP sirve para los 11. Prioridad del usuario primero:
/// Grok, OpenRouter y Kilo Code.
class AiProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String defaultModel;
  final int priority; // 1 = primero
  const AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    required this.priority,
  });
}

const List<AiProvider> AI_PROVIDERS = [
  // ---- prioridad ★ (grok, openrouter, kilo) ----
  AiProvider(
      id: 'grok',
      name: 'xAI Grok',
      baseUrl: 'https://api.x.ai/v1',
      defaultModel: 'grok-3-mini',
      priority: 1),
  AiProvider(
      id: 'openrouter',
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      defaultModel: 'openai/gpt-4o-mini',
      priority: 2),
  AiProvider(
      id: 'kilo',
      name: 'Kilo Code',
      baseUrl: 'https://api.kilo.ai/api/gateway',
      defaultModel: 'anthropic/claude-sonnet-4',
      priority: 3),
  // ---- resto, igual de soportados ----
  AiProvider(
      id: 'groq',
      name: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'llama-3.1-8b-instant',
      priority: 4),
  AiProvider(
      id: 'nvidia',
      name: 'NVIDIA',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      defaultModel: 'meta/llama-3.1-8b-instruct',
      priority: 5),
  AiProvider(
      id: 'cerebras',
      name: 'Cerebras',
      baseUrl: 'https://api.cerebras.ai/v1',
      defaultModel: 'llama3.1-8b',
      priority: 6),
  AiProvider(
      id: 'mistral',
      name: 'Mistral',
      baseUrl: 'https://api.mistral.ai/v1',
      defaultModel: 'mistral-small-latest',
      priority: 7),
  AiProvider(
      id: 'github',
      name: 'GitHub Models',
      baseUrl: 'https://models.inference.ai.azure.com',
      defaultModel: 'gpt-4o-mini',
      priority: 8),
  AiProvider(
      id: 'gemini',
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      defaultModel: 'gemini-2.0-flash',
      priority: 9),
  AiProvider(
      id: 'llm7',
      name: 'LLM7.io',
      baseUrl: 'https://api.llm7.io/v1',
      defaultModel: 'gpt-4o-mini',
      priority: 10),
  AiProvider(
      id: 'cloudflare',
      name: 'Cloudflare AI GW',
      baseUrl: 'https://gateway.ai.cloudflare.com/v1', // requiere cuenta/gw en url
      defaultModel: '@cf/meta/llama-3.1-8b-instruct',
      priority: 11),
];

AiProvider? providerById(String id) {
  for (final p in AI_PROVIDERS) {
    if (p.id == id) return p;
  }
  return null;
}
