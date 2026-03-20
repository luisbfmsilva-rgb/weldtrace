import 'package:flutter/widgets.dart';

/// Simple key-based localization.
///
/// Keys are the canonical English strings; values are translations.
/// Usage:  AppLocalizations.of(context).t('Projects')  → 'Projetos' (PT-BR)
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const delegate = _AppLocalizationsDelegate();

  /// Translate [key] (English source text) to the current locale.
  /// Falls back to the key itself if no translation is found.
  String t(String key) {
    if (locale.languageCode == 'pt') {
      return _pt[key] ?? key;
    }
    return key;
  }

  // ── PT-BR translations ─────────────────────────────────────────────────────
  static const Map<String, String> _pt = {
    // NAVIGATION & MENU
    'Projects': 'Projetos',
    'Welds': 'Soldas',
    'Machines': 'Máquinas',
    'Reports': 'Relatórios',
    'Settings': 'Configurações',
    'Users': 'Usuários',
    'Dashboard': 'Painel',
    'Sign In': 'Entrar',
    'Sign Out': 'Sair',
    'Back to Projects': 'Voltar para Projetos',
    'Email': 'E-mail',
    'Password': 'Senha',
    'Enter your email address first, then tap Forgot Password.':
        'Digite o seu e-mail primeiro, depois clique em "Esqueci minha senha"',
    'Password reset email sent': 'E-mail de redefinição de senha enviado',

    // PROJECTS
    'Active Projects': 'Projetos ativos',
    'All Projects': 'Todos os projetos',
    'New Project': 'Novo projeto',
    'Create Project': 'Criar projeto',
    'Project deleted': 'Projeto excluído',
    'Create your first project to start recording welds.':
        'Crie seu primeiro projeto antes de começar a registrar soldas.',
    'No projects yet.': 'Nenhum projeto cadastrado.',
    'No welds in this project yet.':
        'Nenhuma solda registrada nesse projeto até o momento.',
    'Project not found': 'O projeto não foi encontrado.',
    'This will permanently delete this project. This action cannot be undone.':
        'Essa ação irá excluir esse projeto permanentemente. Essa ação não poderá ser revertida',
    'Recent Welds': 'Soldas recentes',
    'Total Welds': 'Total de soldas',
    'Quick Actions': 'Ações rápidas',
    'Start First Weld': 'Iniciar uma solda',

    // MACHINES
    'New Machine': 'Nova máquina',
    'Add Machine': 'Adicionar máquina',
    'Register Machine': 'Registrar máquina',
    'Machine deleted': 'Máquina excluída',
    'Machine Approved': 'Máquina aprovada',
    'Approved machines can be used in welds':
        'Máquinas aprovadas podem ser utilizadas em soldas',
    'Register your welding machines before starting a weld.':
        'Registre suas máquinas de solda antes de iniciar uma solda.',
    'No machines registered.': 'Nenhuma máquina registrada.',
    'Delete Machine?': 'Excluir máquina?',
    'Hydraulic Cylinder Area': 'Área útil do cilindro [mm²]',
    'Ambient Temperature (°C)': 'Temperatura ambiente (°C)',

    // WELD SETUP
    'New Weld': 'Nova solda',
    'New Weld Setup': 'Configurar nova solda',
    'Butt Fusion': 'Termofusão (solda de topo)',
    'Electrofusion': 'Eletrofusão',
    'Electrofusion — Coming Soon': 'Eletrofusão - Em breve',
    'Pipe Diameter (DE)': 'Diâmetro Externo do tubo (DE)',
    'Pipe Diameter (DN)': 'Diâmetro nominal do tubo (DN)',
    'Pipe Material': 'Material do tubo',
    'SDR': 'SDR',
    'Select diameter': 'Selecionar o diâmetro',
    'Select diameter first': 'Selecionar o diâmetro primeiro',
    'Select material': 'Selecionar o material',
    'Select project': 'Selecionar o projeto',
    'Select SDR': 'Selecionar o SDR',
    'No SDR ratings found for this diameter':
        'Nenhum SDR encontrado para esse diâmetro',
    'Welding Standard': 'Norma de solda',
    'Welding Standard (Optional)': 'Norma de solda (opcional)',
    'Standard Not Yet Available': 'Essa norma não está disponível ainda',
    'Select standard (optional)': 'Selecionar norma (opcional)',
    'Pipe Specification': 'Especificação do tubo',
    'Pipe geometry': 'Geometria do tubo',
    'PE100 — Polyethylene MRS 100': 'PE100 - Polietileno MRS 100',
    'PE80 — Polyethylene MRS 80': 'PE80 - Polietileno MRS 80',
    'PP — Polypropylene': 'PP - Polipropileno',
    'DVS 2207 calculation': 'Cálculo segundo a DVS 2207',
    'Universal': 'Universal',
    'Project & Machine': 'Projeto e máquina',
    'Location & Equipment': 'Localização e equipamento',
    'Start by selecting a project and machine.':
        'Comece selecionando um projeto e uma máquina',
    'Operator Name': 'Nome do soldador',
    'Operator ID / Badge Number': 'ID do soldador/Código de certificação',
    'Notes': 'Observações',
    'Optional': 'Opcional',
    'Optional weld notes…': 'Observações da solda (opcional)',
    'Temperature': 'Temperatura',
    'Joint ID': 'ID da solda',
    'Start Weld': 'Iniciar solda',

    // PREPARATION SCREEN
    'Preparation — Step 1 of 3': 'Preparação - Passo 1 de 3',
    'Preparation — Step 2 of 3': 'Preparação - Passo 2 de 3',
    'Preparation — Step 3 of 3': 'Preparação - Passo 3 de 3',
    'Define Drag Pressure': 'Definir pressão de arrastamento',
    'Ensure no load on the clamps. The machine must move freely.':
        'Garanta que não há carga nas garras. A máquina deve se mover livremente.',
    'Current Pressure': 'Pressão atual [bar]',
    'Define Drag Pressure (button)': 'Definir pressão de arrastamento',
    'Facing the Pipes': 'Faceamento dos tubos',
    'Face both pipe ends until all burrs are removed.':
        'Face as extremidades de ambos os tubos até remover todas as rebarbas.',
    'Maximum Facing Pressure': 'Pressão máxima de faceamento',
    'Facing Done!': 'Faceamento concluído!',
    'Check Alignment & Gap Width': 'Cheque o desalinhamento e a fresta',
    'Maximum Misalignment': 'Desalinhamento máximo',
    '≥ 10 % of wall thickness, rounded to 0.5 mm':
        '≥ 10 % da espessura de parede, arredondado por 0,5mm',
    'Maximum Gap Width': 'Fresta máxima admissível',
    'Maximum gap width checked ✓': 'Fresta checada ✓',
    'Min. Initial Bead Height': 'Altura mínima do cordão inicial [mm]',
    'Done! — Start Welding': 'Pronto! - Iniciar solda',
    'Abort Preparation?': 'Abortar preparação?',
    'Machine Pressure Calculation': 'Pressão calculada pela máquina',
    'Face the Pipes Again': 'Faceamento novamente',

    // SENSOR / BLE
    'BLE Sensor': 'Sensor BLE',
    'Connecting…': 'Conectando...',
    'Connect to Sensor': 'Conectar ao sensor',
    'Disconnect': 'Desconectar',
    'Continue': 'Continuar',
    'Leave': 'Sair',
    'Cancel': 'Cancelar',

    // WELDING SESSION
    'Bead-Up Pressure Adjustment': 'Ajustar a pressão de pré-aquecimento',
    'Bead Up': 'Pré-aquecimento',
    'Heating': 'Aquecimento',
    'Changeover (t3)': 'Retirada da placa de aquecimento',
    'Build-Up (t4)': 'Reposição de pressão',
    'Fusion': 'Fusão',
    'Cooling': 'Resfriamento',
    'Target Machine Pressure': 'Pressão desejada',
    'Max Machine Pressure': 'Pressão máxima',
    'Remaining': 'Restando',
    'Actual': 'Atual',
    'Nominal': 'Nominal',
    'Bead Formed — Done!': 'Cordão formado - Pronto!',
    'Remove Heater Plate — Done!': 'Remover placa de aquecimento - Pronto!',
    'Remove the heater plate and close the machine.':
        'Remova a placa de aquecimento e feche a máquina',
    'Changeover (t4) starts automatically when pressure rises.':
        'A etapa de reposição de pressão inicia automaticamente quando a pressão sobe',
    'Machine closing — maintain fusion pressure':
        'Máquina fechando - mantenha a pressão de solda',
    'Auto-advancing to Cooling when…':
        'Avançar automaticamente para o resfriamento quando...',
    'Keep pressure stable ± 8 % limit':
        'Mantenha a pressão estável dentro do limite de ± 8 %',
    'Cooling Remaining': 'Resfriamento restante',
    'Sensor not connected — pressure will be recorded as 0':
        'Sensor desconectado - a pressão será registrada como 0',
    'Cancel Weld': 'Cancelar solda',
    '[TEST] Done — skip to Cooling': '[TESTE] Pronto - avançar para Resfriamento',
    'Cancel Weld?': 'Cancelar solda?',
    'End Cooling?': 'Finalizar resfriamento?',
    'End Now': 'Finalizar agora',
    'Continue Cooling': 'Continuar resfriamento',
    'Weld cancelled — record saved': 'Solda cancelada - relatório salvo',
    'Weld completed and certified!': 'Solda completa e certificada!',
    'Share Certificate PDF': 'Compartilhar o relatório em PDF',
    'Share PDF': 'Compartilhar PDF',
    'Print': 'Imprimir',
    'Timeline': 'Linha do tempo',
    'Traceability': 'Rastreabilidade',
    'Pressure × Time Graph': 'Gráfico Pressão [bar] x Tempo [s]',
    'No pressure data recorded': 'Nenhum dado de pressão registrado',
    'Chart unavailable': 'Gráfico indisponível',
    'Trace Quality': 'Qualidade da rastreabilidade',
    'Tolerance band': 'Faixa de tolerância',
    'Exceeded maximum duration': 'Tempo máximo excedido',

    // REPORTS / WELDS LIST
    'View Weld Details': 'Veja os detalhes da solda',
    'Complete welds to generate certificates and reports.':
        'Complete soldas para gerar relatórios certificados',
    'No completed welds yet.': 'Nenhuma solda completa até o momento',
    'All': 'Todas',
    'Completed': 'Completas',
    'Pending': 'Em andamento',
    'Failed': 'Falhas',
    'Date': 'Data',
    'Operator': 'Soldador',
    'Operator ID': 'ID do Soldador',
    'Project': 'Projeto',
    'Machine': 'Máquina',
    'Model': 'Modelo',
    'Serial Number': 'Número de série',
    'Pipe Diameter': 'Diâmetro do tubo',
    'Fusion Pressure': 'Pressão de solda',
    'Heating Time': 'Tempo de aquecimento [s]',
    'Cooling Time': 'Tempo de resfriamento [min]',
    'Bead Height': 'Altura do cordão inicial [mm]',
    'Wall Thickness': 'Espessura de parede [mm]',
    'Outer Diameter': 'Diâmetro externo DE [mm]',
    'Weld Parameters': 'Parâmetros de solda',
    'Location (GPS)': 'Localização (GPS)',
    'Verify Weld': 'Verificar solda',
    'QR Verification Code': 'QR Code de verificação da solda',
    'Scan to verify this weld certificate':
        'Escanear QR code para verificar essa solda',
    'PENDING': 'PENDENTE',

    // USER MANAGEMENT
    'User Management': 'Gestão de usuários',
    'Add User': 'Adicionar usuário',
    'Edit User': 'Editar usuário',
    'Delete User': 'Excluir usuário',
    'First Name': 'Nome',
    'Last Name': 'Sobrenome',
    'Role': 'Cargo',
    'Cert. Number (optional)': 'Certificação de soldador (opcional)',
    'Active': 'Ativo',
    'Inactive': 'Inativo',
    'Create': 'Criar',
    'Save': 'Salvar',
    'No users found. Tap + to add one.':
        'Nenhum usuário encontrado. Clique no "+" para adicionar um usuário',
    'You cannot delete your own account':
        'Você não pode deletar sua própria conta',

    // ROLES
    'manager': 'Gerente',
    'supervisor': 'Supervisor',
    'welder': 'Soldador',
    'auditor': 'Auditor',

    // SETTINGS
    'Language': 'Idioma',
    'Sensor Setup': 'Configuração do sensor',
    'Connect & calibrate BLE sensor': 'Conectar e calibrar o sensor BLE',
    'Sync Now': 'Sincronizar agora',
    'Upload pending records and pull updates':
        'Enviar registros pendentes e baixar atualizações',
    'Standards': 'Normas',
    'DVS 2207 · ISO 21307 · ASTM F2620': 'DVS 2207 · ISO 21307 · ASTM F2620',
    'Add, edit and remove users': 'Adicionar, editar e remover usuários',
    'Company Logo': 'Logo da empresa',
    'Upload your company logo for PDF reports':
        'Faça upload do logo da sua empresa para os relatórios PDF',
    'Change Logo': 'Alterar logo',
    'Remove Logo': 'Remover logo',
    'Logo removed': 'Logo removido',
    'Sync completed with errors': 'Sincronização concluída com erros',
    'Sync complete': 'Sincronização concluída',

    // COMMON / ACTIONS
    'OK': 'OK',
    'Close': 'Fechar',
    'Delete': 'Excluir',
    'Edit': 'Editar',
    'Add': 'Adicionar',
    'Search': 'Buscar',
    'Refresh': 'Atualizar',
    'Loading…': 'Carregando...',
    'Error': 'Erro',
    'Success': 'Sucesso',
    'No data': 'Sem dados',
    'Measured Drag Pressure (bar)': 'Pressão de arrastamento medida (bar)',
    'Point at the weld QR code': 'Aponte para o QR code da solda',
    'WELD VERIFIED ✓': 'SOLDA VERIFICADA ✓',
    'SIGNATURE MISMATCH ✗': 'ASSINATURA NÃO CONFERE ✗',
    'WELD NOT FOUND': 'SOLDA NÃO ENCONTRADA',
    'INVALID QR CODE': 'QR CODE INVÁLIDO',
    'Scan Another': 'Escanear outro',
  };
}

// ── Localizations delegate ────────────────────────────────────────────────────

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'pt'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
