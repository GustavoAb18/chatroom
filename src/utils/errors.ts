// Converte erros do Supabase (ou de rede) em mensagens curtas e em português
// para a interface. O texto original nem sempre é amigável — e alguns são
// apenas detalhes técnicos que não ajudam quem está usando o app.

function rawMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;
  if (error && typeof error === 'object' && 'message' in error) {
    return String((error as { message: unknown }).message);
  }
  return '';
}

export function friendlyError(error: unknown): string {
  const message = rawMessage(error).trim();
  const lower = message.toLowerCase();

  if (
    lower.includes('network request failed') ||
    lower.includes('failed to fetch') ||
    lower.includes('networkerror') ||
    lower.includes('network error') ||
    lower.includes('sem conexão')
  ) {
    return 'Sem conexão com a internet.';
  }

  if (lower.includes('invalid login credentials')) {
    return 'E-mail ou senha incorretos.';
  }

  if (lower.includes('email not confirmed')) {
    return 'Confirme seu e-mail antes de entrar.';
  }

  if (lower.includes('user already registered')) {
    return 'Já existe uma conta com este e-mail.';
  }

  if (lower.includes('password should be at least')) {
    return 'A senha é curta demais.';
  }

  if (lower.includes('row-level security')) {
    return 'Você não tem permissão para esta ação. Execute o arquivo supabase/corrigir-banco.sql no Supabase e tente de novo.';
  }

  if (lower.includes('permission denied')) {
    return 'O banco não deu permissão para esta ação. Execute o arquivo supabase/corrigir-banco.sql no Supabase e tente de novo.';
  }

  if (lower.includes('foreign key') || lower.includes('violates foreign key constraint')) {
    return 'Seu perfil não foi encontrado no banco. Execute o arquivo supabase/corrigir-banco.sql no Supabase e tente de novo.';
  }

  if (
    lower.includes('could not find the table') ||
    (lower.includes('relation') && lower.includes('does not exist')) ||
    (lower.includes('column') && lower.includes('does not exist'))
  ) {
    return 'O banco está desatualizado. Execute o arquivo supabase/corrigir-banco.sql no Supabase e tente de novo.';
  }

  if (lower.includes('jwt expired') || lower.includes('invalid jwt')) {
    return 'Sua sessão expirou. Saia e entre novamente.';
  }

  if (lower.includes('duplicate key')) {
    return 'Você já está nesta sala.';
  }

  return message || 'Algo deu errado. Tente novamente.';
}
