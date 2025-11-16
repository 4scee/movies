import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// 1. IMPORTACIÓN CRÍTICA: Se asume que este archivo fue generado por FlutterFire CLI
// Reemplaza con tu archivo real después de ejecutar 'flutterfire configure'
import 'firebase_options.dart';
import 'dart:async';

// ----------------------------------------------------------------------------
// 1. MODELO DE DATOS
// ----------------------------------------------------------------------------

class Movie {
  final String id;
  final String title;
  final int year;
  final String director;
  final String genre;
  final String synopsis;
  final String imageUrl;

  Movie({
    required this.id,
    required this.title,
    required this.year,
    required this.director,
    required this.genre,
    required this.synopsis,
    required this.imageUrl,
  });

  // Constructor para crear un objeto Movie desde un DocumentSnapshot de Firestore
  factory Movie.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data()!;
    return Movie(
      id: snapshot.id,
      title: data['title'] ?? 'Sin título',
      // Manejo de tipo seguro para el año (puede venir como string o int)
      year: (data['year'] is int)
          ? data['year']
          : int.tryParse(data['year'].toString()) ?? 0,
      director: data['director'] ?? 'Desconocido',
      genre: data['genre'] ?? 'General',
      synopsis: data['synopsis'] ?? 'Sin sinopsis disponible.',
      imageUrl:
          data['imageUrl'] ??
          'https://placehold.co/200x300/CCCCCC/333333?text=No+Image',
    );
  }

  // Método para convertir el objeto Movie a un Map para Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'year': year,
      'director': director,
      'genre': genre,
      'synopsis': synopsis,
      'imageUrl': imageUrl,
      // Campo para ordenar. Solo se incluye si no estamos actualizando un objeto existente
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}

// ----------------------------------------------------------------------------
// 2. SERVICIOS REALES DE FIREBASE
// ----------------------------------------------------------------------------

// SERVICIO DE AUTENTICACIÓN REAL
class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Función para REGISTRAR un nuevo usuario con email y contraseña
  Future<User?> register(String email, String password, String name) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await userCredential.user!.updateDisplayName(name);
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthError(e.code));
    } catch (e) {
      throw Exception('Error desconocido al registrar: $e');
    }
  }

  // Función para INICIAR SESIÓN con email y contraseña
  Future<User?> login(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthError(e.code));
    } catch (e) {
      throw Exception('Error desconocido al iniciar sesión: $e');
    }
  }

  // Función para CERRAR SESIÓN
  Future<void> logout() async {
    await _auth.signOut();
  }

  // Función para actualizar perfil.
  Future<void> updateUserProfile(String newName) async {
    if (_auth.currentUser != null) {
      await _auth.currentUser!.updateDisplayName(newName);
    }
  }

  // Convierte códigos de error de Firebase a mensajes legibles
  String _handleAuthError(String errorCode) {
    switch (errorCode) {
      case 'weak-password':
        return 'La contraseña es demasiado débil.';
      case 'email-already-in-use':
        return 'La cuenta ya existe para ese correo.';
      case 'user-not-found':
        return 'No se encontró un usuario para ese correo.';
      case 'wrong-password':
        return 'Contraseña incorrecta.';
      case 'invalid-email':
        return 'El formato del correo electrónico es inválido.';
      default:
        return 'Error de autenticación: $errorCode';
    }
  }
}

// SERVICIO DE BASE DE DATOS REAL (Firestore)
class DatabaseService {
  // Colección de películas con conversión automática
  CollectionReference<Movie> get _moviesCollection => FirebaseFirestore.instance
      .collection('movies')
      .withConverter<Movie>(
        fromFirestore: (snapshot, _) => Movie.fromFirestore(snapshot),
        toFirestore: (movie, _) => movie.toFirestore(),
      );

  // READ: Stream de películas. Ordenado por timestamp (la fecha de creación)
  Stream<List<Movie>> get simplifiedMoviesStream {
    return _moviesCollection
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  // CREATE: Agrega una nueva película
  Future<void> addMovie(Movie movie) async {
    // add() crea un ID automáticamente en Firestore
    await _moviesCollection.add(movie);
  }

  // UPDATE: Actualiza una película existente
  Future<void> updateMovie(Movie movie) async {
    // set() usa el ID existente de la película (movie.id)
    // Usamos update() para no sobreescribir el 'timestamp' si existe
    await FirebaseFirestore.instance.collection('movies').doc(movie.id).update({
      'title': movie.title,
      'year': movie.year,
      'director': movie.director,
      'genre': movie.genre,
      'synopsis': movie.synopsis,
      'imageUrl': movie.imageUrl,
    });
  }

  // DELETE: Elimina una película
  Future<void> deleteMovie(String id) async {
    await _moviesCollection.doc(id).delete();
  }
}

// Instancias de servicio globales (se inicializan en main)
final AuthService _authService = AuthService();
// Se inicializa en main() después de Firebase.initializeApp()
late DatabaseService _dbService;

// ----------------------------------------------------------------------------
// 3. CONFIGURACIÓN INICIAL Y MAIN (FIXED)
// ----------------------------------------------------------------------------

void main() async {
  // Inicialización crítica de Flutter y Firebase
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // *** FIX CRÍTICO: Usamos las opciones de la plataforma generadas automáticamente ***
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Inicializar el servicio de base de datos *después* de la inicialización de Firebase
    _dbService = DatabaseService();
    debugPrint("Firebase inicializado correctamente.");
  } catch (e) {
    debugPrint(
      "Error CRÍTICO al inicializar Firebase: $e. Revisa tu archivo firebase_options.dart.",
    );
    // Muestra un mensaje en la consola si Firebase falla.
  }

  runApp(const MyApp());
}

// ----------------------------------------------------------------------------
// 4. WIDGET PRINCIPAL Y MANEJO DE ESTADO (MainApp, AuthWrapper)
// ----------------------------------------------------------------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Catálogo de Películas CRUD & Auth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1E88E5), // Color primario
        useMaterial3: true,
        // Custom theme for app bar and buttons
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Escucha los cambios de estado de autenticación REAL de Firebase
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Si hay un usuario (autenticado), vamos a la pantalla principal.
        if (snapshot.hasData && snapshot.data != null) {
          return MainScreen(user: snapshot.data!);
        }

        // Si no hay usuario, vamos a la pantalla de bienvenida.
        return const WelcomeScreen();
      },
    );
  }
}
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.7);
  int _currentPage = 0;
  late final List<String> _bannerImages = [
  'assets/2.jpg',
  'assets/4.jpg',
  'assets/6.jpg',
  'assets/7.jpg',
  'assets/8.jpg',
  'assets/9.jpg',
  'assets/10.jpg',
];

  @override
  void initState() {
    super.initState();
    // Auto-slide cada 3 segundos
    Future.delayed(const Duration(seconds: 3), _nextPage);
  }

  void _nextPage() {
    if (_pageController.hasClients) {
      _currentPage = (_currentPage + 1) % _bannerImages.length;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      Future.delayed(const Duration(seconds: 3), _nextPage);
    }
  }

 Widget _buildBannerImage(String path) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6.0),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9, // 🔥 Todas las imágenes con la misma proporción
        child: Image.asset(
          path,
          fit: BoxFit.cover, // 🔥 No se deforma NUNCA
        ),
      ),
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
         child: Image.asset('assets/1.jpg', fit: BoxFit.cover),
         ),

          Container(color: Colors.black.withOpacity(0.3)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                 height: MediaQuery.of(context).size.width * 0.45, 
                 child: PageView.builder(
                 controller: _pageController,
                 itemCount: _bannerImages.length,
                 onPageChanged: (index) {
             setState(() => _currentPage = index);
              },
           itemBuilder: (context, index) {
          return _buildBannerImage(_bannerImages[index]);
        },
     ),
    ),

                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _bannerImages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _currentPage == index ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index ? Colors.white : Colors.white54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    '¡Hola mundo!',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Inicia sesión o regístrate para acceder al catálogo.',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 60),
                ElevatedButton(
                 onPressed: () {
                 Navigator.push(
                 context,
                 MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                 },
                  child: const Text('Ingresar'),
                 ),

                  const SizedBox(height: 20),
                 OutlinedButton(
                 onPressed: () {
                  Navigator.push(
                 context,
                 MaterialPageRoute(builder: (_) => const RegisterScreen()),
                 );
                  },
                  child: const Text('Registrarse'),
                ),

                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.login(emailController.text, passwordController.text);
      if (mounted)
        Navigator.pop(
          context,
        ); // Éxito: AuthWrapper se encargará de la navegación
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ingresar')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Ingrese un correo' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Ingrese una contraseña'
                      : null,
                ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Iniciar Sesión',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.register(
        emailController.text,
        passwordController.text,
        nameController.text,
      );
      if (mounted) Navigator.pop(context); // Éxito
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrarse')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Ingrese su nombre' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Ingrese un correo' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña (Mín. 6 caracteres)',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (v) => (v == null || v.length < 6)
                      ? 'La contraseña debe tener al menos 6 caracteres'
                      : null,
                ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Crear Cuenta',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 6. PANTALLA PRINCIPAL (MainScreen con Navegación y Perfil)
// ----------------------------------------------------------------------------

class MainScreen extends StatefulWidget {
  final User user;
  const MainScreen({super.key, required this.user});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Inicializar _dbService en tiempo de ejecución (aunque ya se hace en main, es bueno asegurar)
  @override
  void initState() {
    super.initState();
  }

  late final List<Widget> _widgetOptions = <Widget>[
    const MovieCatalogScreen(),
    const AdminScreen(),
    ProfileScreen(user: widget.user),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (mounted) Navigator.pop(context); // Cierra el Drawer si está abierto
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentTitle = _getTitle();

    return Scaffold(
      appBar: AppBar(
        title: Text(currentTitle),
        // Botón de perfil visible en el AppBar para un acceso más rápido
        actions: [
          if (_selectedIndex == 2 && currentTitle == 'Mi Perfil')
            // No se necesita acción extra si ya estamos en Perfil
            const SizedBox.shrink()
          else if (_selectedIndex != 2)
            IconButton(
              icon: const Icon(Icons.person),
              tooltip: 'Ver Perfil',
              onPressed: () => setState(() => _selectedIndex = 2),
            ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF1E88E5)),
              accountName: Text(
                widget.user.displayName ?? 'Usuario',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              accountEmail: Text(widget.user.email ?? 'Sin Correo'),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Color(0xFF1E88E5)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.movie),
              title: const Text('Catálogo de Películas'),
              selected: _selectedIndex == 0,
              onTap: () => _onItemTapped(0),
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Administración (CRUD)'),
              selected: _selectedIndex == 1,
              onTap: () => _onItemTapped(1),
            ),
            ListTile(
              leading: const Icon(Icons.person_pin),
              title: const Text('Mi Perfil'),
              selected: _selectedIndex == 2,
              onTap: () => _onItemTapped(2),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Cerrar Sesión'),
              onTap: () {
                _authService.logout();
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
    );
  }

  String _getTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Catálogo de Películas';
      case 1:
        return 'Panel de Administración';
      case 2:
        return 'Mi Perfil';
      default:
        return 'Catálogo';
    }
  }
}

// ----------------------------------------------------------------------------
// 7. PANTALLA DE PERFIL DE USUARIO
// ----------------------------------------------------------------------------

class ProfileScreen extends StatefulWidget {
  final User user;
  const ProfileScreen({super.key, required this.user});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Aseguramos que el controlador tenga el valor inicial del nombre
    _nameController = TextEditingController(
      text: widget.user.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_nameController.text.isEmpty) {
      setState(() {
        _message = 'El nombre no puede estar vacío.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await _authService.updateUserProfile(_nameController.text);
      // Forzar una actualización de la interfaz para reflejar el nuevo nombre
      // Esto es crucial para que el drawer y la pantalla principal se actualicen
      await FirebaseAuth.instance.currentUser!.reload();
      setState(() {
        _isEditing = false;
        _message = 'Nombre actualizado correctamente.';
      });
    } catch (e) {
      setState(() {
        _message = 'Error al actualizar: $e';
      });
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Usar la instancia actual del usuario para obtener el nombre más reciente
    // Necesario porque el widget padre (MainScreen) no se reconstruye automáticamente
    final currentUser = FirebaseAuth.instance.currentUser;
    final displayName = currentUser?.displayName ?? 'Usuario';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.person_2, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 30),

            Text(
              'Correo: ${currentUser?.email ?? 'N/A'}',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            Text(
              'UID: ${currentUser?.uid ?? 'N/A'}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 40),

            if (_isEditing)
              Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nuevo Nombre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _isSaving ? null : _handleSave,
                        child: _isSaving
                            ? const CircularProgressIndicator.adaptive()
                            : const Text('Guardar'),
                      ),
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _isEditing = false;
                          _nameController.text =
                              displayName; // Restaura el valor
                          _message = null;
                        }),
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                ],
              )
            else
              Column(
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {
                      _isEditing = true;
                      _nameController.text = displayName;
                      _message = null;
                    }),
                    icon: const Icon(Icons.edit),
                    label: const Text('Editar mi información'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(200, 45),
                    ),
                  ),
                ],
              ),

            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _message!.contains('Error')
                        ? Colors.red
                        : Colors.green,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 8. CATÁLOGO DE PELÍCULAS (READ)
// ----------------------------------------------------------------------------

class MovieCatalogScreen extends StatelessWidget {
  const MovieCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Movie>>(
      stream: _dbService.simplifiedMoviesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error al cargar datos: ${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }
        final movies = snapshot.data ?? [];

        if (movies.isEmpty) {
          return const Center(
            child: Text(
              'Aún no hay películas en el catálogo. ¡Añade algunas en Admin!',
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12.0),
          itemCount: movies.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.65,
            crossAxisSpacing: 12.0,
            mainAxisSpacing: 12.0,
          ),
          itemBuilder: (context, index) {
            final movie = movies[index];
            return MovieCard(movie: movie);
          },
        );
      },
    );
  }
}

// MovieCard y MovieDetailScreen (sin cambios significativos)

class MovieCard extends StatelessWidget {
  final Movie movie;
  const MovieCard({super.key, required this.movie});

  Widget _buildPosterWithLoading(String imageUrl) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
              backgroundColor: Colors.white24,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey[800],
        alignment: Alignment.center,
        child: const Icon(
          Icons.image_not_supported,
          color: Colors.white,
          size: 40,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MovieDetailScreen(movie: movie),
          ),
        );
      },
      child: Card(
        elevation: 6,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              flex: 4,
              child: Container(
                color: Colors.black,
                child: _buildPosterWithLoading(movie.imageUrl),
              ),
            ),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Center(
                  child: Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MovieDetailScreen extends StatelessWidget {
  final Movie movie;
  const MovieDetailScreen({super.key, required this.movie});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(movie.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.network(
                  movie.imageUrl,
                  height: 300,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 300,
                    width: 200,
                    color: Colors.grey[300],
                    alignment: Alignment.center,
                    child: const Text(
                      'No hay imagen',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildDetailRow('Título', movie.title, Icons.title),
            _buildDetailRow('Año', movie.year.toString(), Icons.calendar_today),
            _buildDetailRow('Director', movie.director, Icons.person),
            _buildDetailRow('Género', movie.genre, Icons.category),
            const SizedBox(height: 20),
            const Text(
              'Sinopsis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Text(movie.synopsis, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blueAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 9. PANTALLA DE ADMINISTRACIÓN (CRUD)
// ----------------------------------------------------------------------------

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Solo permitir el acceso al CRUD si el usuario está autenticado
    if (FirebaseAuth.instance.currentUser == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            'Debe iniciar sesión para acceder a la administración.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    return Scaffold(
      body: StreamBuilder<List<Movie>>(
        // Usamos el Stream corregido 'simplifiedMoviesStream'
        stream: _dbService.simplifiedMoviesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Error al cargar datos: ${snapshot.error}'),
            );
          }
          final movies = snapshot.data ?? [];

          if (movies.isEmpty) {
            return const Center(
              child: Text(
                'Presiona el botón "+" para añadir la primera película.',
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(
              top: 8.0,
              bottom: 80.0,
            ), // Padding extra para el FAB
            itemCount: movies.length,
            itemBuilder: (context, index) {
              final movie = movies[index];
              return MovieAdminTile(movie: movie);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Crear (CRUD: C)
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MovieFormScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Añadir Película'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class MovieAdminTile extends StatelessWidget {
  final Movie movie;
  const MovieAdminTile({super.key, required this.movie});

  // Función para mostrar el diálogo de confirmación de eliminación//
  void _showDeleteConfirmation(BuildContext context, Movie movie) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text(
          '¿Estás seguro de que deseas eliminar la película "${movie.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _dbService.deleteMovie(movie.id);
              Navigator.pop(context);
            },
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      elevation: 2,
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4.0),
          child: Image.network(
            movie.imageUrl,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image, size: 40),
          ),
        ),
        title: Text(
          movie.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${movie.director} (${movie.year})'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // UPDATE (CRUD: U)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.orange),
              tooltip: 'Editar',
              onPressed: () {
                Navigator.push(
                  context,
                  // Navega a la pantalla de formulario en modo edición
                  MaterialPageRoute(
                    builder: (context) => MovieFormScreen(movie: movie),
                  ),
                );
              },
            ),
            // DELETE (CRUD: D)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Eliminar',
              onPressed: () => _showDeleteConfirmation(context, movie),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 10. FORMULARIO DE CREACIÓN/EDICIÓN (CRUD: C & U)
// ----------------------------------------------------------------------------

class MovieFormScreen extends StatefulWidget {
  // Si 'movie' es null, estamos creando. Si no es null, estamos editando.
  final Movie? movie;
  const MovieFormScreen({super.key, this.movie});

  @override
  State<MovieFormScreen> createState() => _MovieFormScreenState();
}

class _MovieFormScreenState extends State<MovieFormScreen> {
  final formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Controladores
  late final TextEditingController titleController;
  late final TextEditingController yearController;
  late final TextEditingController directorController;
  late final TextEditingController genreController;
  late final TextEditingController synopsisController;
  late final TextEditingController imageUrlController;

  @override
  void initState() {
    super.initState();
    // Inicializar controladores con valores existentes si estamos editando, o vacíos si estamos creando
    titleController = TextEditingController(text: widget.movie?.title ?? '');
    yearController = TextEditingController(
      text: widget.movie?.year.toString() ?? '',
    );
    directorController = TextEditingController(
      text: widget.movie?.director ?? '',
    );
    genreController = TextEditingController(text: widget.movie?.genre ?? '');
    synopsisController = TextEditingController(
      text: widget.movie?.synopsis ?? '',
    );
    imageUrlController = TextEditingController(
      text:
          widget.movie?.imageUrl ??
          'https://placehold.co/200x300/CCCCCC/333333?text=Movie+Poster',
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    yearController.dispose();
    directorController.dispose();
    genreController.dispose();
    synopsisController.dispose();
    imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    // Crear el objeto Movie a partir de los controladores
    final newMovie = Movie(
      id:
          widget.movie?.id ??
          '', // Si estamos creando, el ID se ignora en addMovie()
      title: titleController.text,
      year: int.tryParse(yearController.text) ?? 0,
      director: directorController.text,
      genre: genreController.text,
      synopsis: synopsisController.text,
      imageUrl: imageUrlController.text,
    );

    try {
      if (widget.movie == null) {
        // CREATE
        await _dbService.addMovie(newMovie);
        if (mounted) {
          _showSnackBar(context, 'Película creada exitosamente.');
          Navigator.pop(context);
        }
      } else {
        // UPDATE
        await _dbService.updateMovie(newMovie);
        if (mounted) {
          _showSnackBar(context, 'Película actualizada exitosamente.');
          Navigator.pop(context);
        }
      }
    } catch (e) {
      _showSnackBar(context, 'Error al guardar: $e', isError: true);
    } finally {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.movie != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Película' : 'Añadir Nueva Película'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: formKey,
          child: Column(
            children: <Widget>[
              _buildTextField(titleController, 'Título', isRequired: true),
              _buildTextField(
                yearController,
                'Año de Estreno',
                isRequired: true,
                keyboardType: TextInputType.number,
                validator: (v) => (v != null && int.tryParse(v) == null)
                    ? 'Debe ser un número válido'
                    : null,
              ),
              _buildTextField(directorController, 'Director', isRequired: true),
              _buildTextField(genreController, 'Género'),
              _buildTextField(
                imageUrlController,
                'URL de la Imagen',
                isRequired: true,
              ),
              _buildTextField(
                synopsisController,
                'Sinopsis',
                maxLines: 5,
                isRequired: true,
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          isEditing ? 'Guardar Cambios' : 'Crear Película',
                          style: const TextStyle(fontSize: 18),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    bool isRequired = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: isRequired
              ? const Icon(Icons.star, size: 12, color: Colors.red)
              : null,
        ),
        validator: (v) {
          if (isRequired && (v == null || v.isEmpty)) {
            return 'Este campo es obligatorio.';
          }
          return validator?.call(v);
        },
      ),
    );
  }
}
